-- contants
local LAUNCH = "/home/hxero/isolated/box i"; -- window to launch (can be non-terminal)

local BOX_PATH   = "/home/hxero/baprocess/output/boxes.bin"; -- path to the generated bin file
local AUDIO_PATH = "/home/hxero/baprocess/badapple.webm";

local MAX_BOXES = 153; -- the `most boxes` from python
local FPS       = 30;  -- 1-30 framerate (sync playback)

local SCALE    = 24;  -- scale  -> resolution height / (grid height)
local OFFSET_X = 192; -- center -> [(resolution width) - (grid width * scale)] / 2
local OFFSET_Y = 46;  -- depends on your top|bottom bars

-- variables
local timer, animation, execute, dispatch, on_event, window_rule =
	hl.timer, hl.animation, hl.exec_cmd, hl.dispatch, hl.on, hl.window_rule;

local window_dsp = hl.dsp.window;
local window_move, window_resize, window_tag, window_close =
	window_dsp.move, window_dsp.resize, window_dsp.tag, window_dsp.close;

local floor = math.floor;

-- utils
local function defer(fn, delay)
	timer(fn, { timeout = tonumber(delay) or 1, type = "oneshot", });
end;

-- guards

-- i'm sorry these look disgusting
-- but, people do stupid thing and blame the script
-- so, these guards just blame the user

local assert = function(condition, message, ...)
	if (condition == nil or condition == false) then
		defer(function()
			package.loaded["badapple"] = nil;
		end);
		error(message);
	end;
	return condition, message, ...;
end;

local require = function(modname)
	local module = require(modname);
	local ok = type(module) ~= "table" or next(module) ~= nil;
	if (not ok) then
		defer(function()
			package.loaded[modname] = nil;
		end);
	end;
	assert(ok, modname .. " - MODULE NOT FOUND\nplease read the readme properly");
	return module;
end;

local function validate_file(path)
	return os.rename(path, path);
end;

assert(validate_file(BOX_PATH),   "BOX_PATH invalid path\n" .. BOX_PATH);
assert(validate_file(AUDIO_PATH), "AUDIO_PATH invalid path\n" .. AUDIO_PATH);

assert(
	type(MAX_BOXES) == "number" and floor(MAX_BOXES) >= 0,
	"MAX_BOXES must be a valid integer above 0");
assert(
	type(SCALE) == "number" and floor(SCALE) >= 0,
	"SCALE must be a valid integer above 0");
assert(
	type(FPS) == "number" and (floor(FPS) > 1 and floor(FPS) <= 30),
	"FPS must be a valid integer between 1 and 30");

assert(type(OFFSET_X) == "number", "OFFSET_X must be a valid integer");
assert(type(OFFSET_Y) == "number", "OFFSET_Y must be a valid integer");

MAX_BOXES, FPS, SCALE, OFFSET_X, OFFSET_Y =
	floor(MAX_BOXES), floor(FPS), floor(SCALE), floor(OFFSET_X), floor(OFFSET_Y);

local box_file = assert(io.open(BOX_PATH, "rb"));

-- modules
local now = require("timeing"); -- > fn(void): time
--          just a copy of luasocket .gettime

-- init
-- killswitch for debugging
defer(function()
	-- defered because, i had SUPER + U to execute from main config
	-- and it would interfere somehow
	hl.unbind("SUPER + U");
	hl.bind("SUPER + U", function()
		-- replace box with the process name, e.g. kitty
		execute("killall box mpv&&hyprctl reload||hyprctl reload");
	end);
end);
-- ]]

window_rule({
	match = { tag = "bad_apple", },
	float = true,

	no_shadow        = true,
	no_blur          = true,
	no_anim          = true,
	no_dim           = true,
	no_focus         = true,
	no_initial_focus = true,

	suppress_event = "activatefocus",

	border_size  = 2,
	opacity      = "0.95 override",
	border_color = "rgba(fef2f299) rgba(fef2f299)",
	rounding     = 0,

	no_max_size = true,
	min_size    = { 0, 0, },
	size        = { 900, 600, },
});

window_rule({ match = { tag = "ba_hidden", }, opacity = "0.0 override", });

for _, v in ipairs({ "windows", "windowsIn", "windowsOut", "windowsMove", "fade", }) do
	animation({ leaf = v, speed = 1, enabled = false, });
end;

local pool_selector = {}; do
	local index = 1;
	-- this instead of for loop to try and avoid crashes from batch launching
	local resume = true;
	local spawner; spawner = timer(function()
		if (not resume) then return; end;
		if (index > MAX_BOXES) then
			-- execute(
			-- 	[[foot -o main.locked-title=yes -Tbad_progress -- \
			-- 	sh -c 'hyprctl rollinglog -f | grep "bad_apple PROG"']]
			-- );

			return spawner:set_enabled(false);
		end;

		execute(LAUNCH, { tag = "+bad_apple", });
		index = index + 1;
		resume = false;
	end, { timeout = 4, type = "repeat", });

	on_event("window.open", function(window)
		for _, t in ipairs(window.tags) do
			if (t == "bad_apple*") then
				resume = true;
				pool_selector[#pool_selector + 1] = "address:" .. window.address;
			end;
		end;
	end);
end;

local is_hidden = {};
local prev_x, prev_y = {}, {};
local prev_w, prev_h = {}, {};

-- i was really trying to improve the performance
-- so i gotta use any micro-optimizing i know ok.
-- avoid gc stutter
local _resize_arg = { window = nil, x = 0, y = 0, };
local _move_arg   = { window = nil, x = 0, y = 0, };
local _tag_arg    = { window = nil, tag = nil, };

local function hide(i)
	if (is_hidden[i]) then return; end;

	_tag_arg.window = pool_selector[i];
	_tag_arg.tag = "+ba_hidden";
	dispatch(window_tag(_tag_arg));

	is_hidden[i] = true;
	prev_x[i], prev_y[i] = nil, nil;
	prev_w[i], prev_h[i] = nil, nil;
end;

local chunks_read = 0;
local frames, frame = {}, {};

local LOAD_CHUNKS = 500;
local loader; loader = timer(function()
	-- load frames into cache
	for _ = 1, LOAD_CHUNKS, 1 do
		local chunk = box_file:read(4);
		if (not chunk or #chunk < 4) then
			-- end of file
			box_file:close();
			print("bad_apple PROG: loaded " .. #frames .. " frames");

			return loader:set_enabled(false);
		end;

		local x, y, w, h = chunk:byte(1, 4);
		if (x == 0 and y == 0 and w == 0 and h == 0) then
			-- append frame and reset frame
			frames[#frames + 1] = frame;
			frame = {};
		else
			-- append box to frame
			frame[#frame + 1] = { x * SCALE, y * SCALE, w * SCALE, h * SCALE, };
		end;

		chunks_read = chunks_read + 1;
	end;

	if (chunks_read % 2500 < LOAD_CHUNKS) then
		print("bad_apple PROG: loading... " .. #frames .. " frames");
	end;
end, { timeout = 4, type = "repeat", });

local watcher; watcher = timer(function()
	-- starts when `loader` finishes caching frames
	-- and all the windows are opened
	if (loader:is_enabled() or #pool_selector < MAX_BOXES) then return; end;

	loader:set_enabled(false);
	watcher:set_enabled(false);

	dispatch(window_close({ window = "title:bad_progress", }));
	print("bad_apple: starting");

	for i = 1, MAX_BOXES, 1 do
		hide(i);
	end;

	execute("mpv --pause --input-ipc-server=/tmp/mpvsocket " .. AUDIO_PATH .. " &");
	defer(function()
		local prev = {};
		local frame_index = 1;
		local start_time = now();
		-- syncing
		execute(
			[[echo 'set pause no' | socat - /tmp/mpvsocket]]
		);

		timer(function()
			local elapsed = now() - start_time;
			local target = floor(elapsed * 30) + 1;
			if (target > frame_index) then
				-- sync frame
				frame_index = target;
			end;

			local boxes = frames[frame_index];
			if (not boxes) then return; end;

			for i = 1, #boxes, 1 do
				local box    = boxes[i];
				local hidden = is_hidden[i];

				local x, y, w, h   = box[1], box[2], box[3], box[4];
				local size_changed = prev_w[i] ~= w or prev_h[i] ~= h;
				local pos_changed  = prev_x[i] ~= x or prev_y[i] ~= y;

				if (not hidden and not size_changed and not pos_changed) then
					-- didn't change from previous frame
					goto continue;
				end;

				local sel = pool_selector[i];
				if (hidden or size_changed) then
					_resize_arg.window = sel;
					_resize_arg.x, _resize_arg.y = w, h;
					dispatch(window_resize(_resize_arg));

					prev_w[i], prev_h[i] = w, h;
				end;

				if (hidden or size_changed or pos_changed) then
					_move_arg.window         = sel;
					_move_arg.x, _move_arg.y = OFFSET_X + x, OFFSET_Y + y;
					dispatch(window_move(_move_arg));

					prev_x[i], prev_y[i] = x, y;
				end;

				if (hidden) then
					_tag_arg.window = sel;
					_tag_arg.tag    = "-ba_hidden";
					dispatch(window_tag(_tag_arg));

					is_hidden[i] = false;
				end;

				prev[i] = box;
				::continue::
			end;

			for i = #boxes + 1, MAX_BOXES, 1 do
				if (prev[i]) then
					hide(i); prev[i] = nil;
				end;
			end;
			frame_index = frame_index + 1;
		end, { timeout = (1000 / FPS), type = "repeat", });
	end, 500);
end, { timeout = 100, type = "repeat", });
