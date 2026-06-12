-- variables
local timer, animation, execute, dispatch, on_event, window_rule =
	hl.timer, hl.animation, hl.exec_cmd, hl.dispatch, hl.on, hl.window_rule;

local window_dsp = hl.dsp.window;
local window_move, window_resize, window_tag, window_close =
	window_dsp.move, window_dsp.resize, window_dsp.tag, window_dsp.close;
local get_windows = hl.get_windows;

local type = type;

local floor = math.floor;

-- utils
local abort_signal = false; -- abort everything

local defer, cycle; do
	local handler = function(fn, abort, opt)
		local self; self = timer(function()
			if (abort_signal) then
				self:set_enabled(false);
				abort();

				collectgarbage("collect");
				return;
			end;
			fn();
		end, opt);

		return self;
	end;

	local dopt = { timeout = 1, type = "oneshot", };
	defer = function(fn, delay, abort)
		dopt.timeout = tonumber(delay) or 1;
		return handler(fn, abort, dopt);
	end;

	local copt = { timeout = 100, type = "repeat", };
	cycle = function(fn, delay, abort)
		copt.timeout = tonumber(delay) or 100;
		return handler(fn, abort, copt);
	end;
end;

local function t_find(t, v)
	for i = 1, #t do
		if t[i] == v then
			return i;
		end;
	end;
end;

--- @diagnostic disable-next-line: unused-local
local notify; do
	local dump;
	local notify_create = hl.notification.create;
	local _arg = { timeout = 5000, };

	--- @diagnostic disable-next-line: unused-function, unused-local
	notify = function(...)
		if (not dump) then dump = require("utils.dump"); end;
		-- debug
		local str = { ..., };
		for i = 1, #str do
			str[i] = dump(str[i]);
		end;

		_arg.text = table.concat(str, "\n");
		notify_create(_arg);
	end;
end;

-- guards

-- i'm sorry these look disgusting
-- but, people do stupid thing and blame the script
-- so, these guards just blame the user

local assert = function(condition, message, ...)
	if (condition == nil or condition == false) then
		defer(function()
			-- debugging
			-- clear cache if loaded from require
			package.loaded["badapple"] = nil;
		end);
		error(message);
	end;
	return condition, message, ...;
end;

local require = function(modname)
	-- ensure module exist before running
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

-- to work with `hyprctl eval` in different path
-- make the require to load from current dir instead of root
local current_file = debug.getinfo(1, "S").source;
assert(
	current_file and current_file:sub(1, 1) == "@", -- @/home/..
	"unable to get current directory");

-- remove filename from path
local current_dir = current_file:sub(2):match("(.*/)") or "./";
package.cpath = current_dir .. "?.so;" .. package.cpath;
package.path = current_dir .. "?.lua;" .. package.path;

local function relative_path(path)
	return path:sub(1, 1) == "/" and path or current_dir .. "/" .. path;
end;

local function validate_file(path)
	local correct_path = relative_path(path);
	return os.rename(correct_path, correct_path);
end;

local config = require("config");
local LAUNCH, BOX_PATH, AUDIO_PATH, MAX_BOXES, SCALE, FPS, OFFSET_X, OFFSET_Y =
	config.LAUNCH, config.BOX_PATH, config.AUDIO_PATH,
	config.MAX_BOXES, config.SCALE, config.FPS,
	config.OFFSET_X, config.OFFSET_Y;

assert(type(LAUNCH) == "string", "Invalid launch command (LAUNCH)");

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

-- correction
MAX_BOXES, FPS, SCALE, OFFSET_X, OFFSET_Y =
	floor(MAX_BOXES), floor(FPS), floor(SCALE), floor(OFFSET_X), floor(OFFSET_Y);

BOX_PATH, AUDIO_PATH =
	relative_path(BOX_PATH), relative_path(AUDIO_PATH);

local box_file = assert(io.open(BOX_PATH, "rb"));

-- modules
local now = require("meti"); -- > fn(void): time
--          just a copy of luasocket .gettime

-- init
-- killswitch for debugging
defer(function()
	-- defered because, i had SUPER + U to execute from main config
	-- and it would interfere somehow
	hl.unbind("SUPER + U");
	hl.bind("SUPER + U", function()
		-- replace box with the process name, e.g. kitty
		abort_signal = true;
		local _arg   = {};

		local debounce;
		local killer; killer = hl.timer(function()
			local windows = get_windows({ tag = "bad_apple*", });

			if (#windows == 0) then
				if (not debounce) then
					debounce = true;
					execute("sleep 0.1 ; hyprctl reload && pkill mpv");
				end;
				killer:set_enabled(false);
				return;
			end;

			local target = windows[1];
			if (target) then
				_arg.window = target;
				dispatch(window_dsp.kill(_arg));
			end;
		end, { timeout = 4, type = "repeat", });
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

do
	local _arg = { speed = 1, enabled = false, };
	for _, v in ipairs({ "windows", "windowsIn", "windowsOut", "windowsMove", "fade", }) do
		_arg.leaf = v;
		animation(_arg);
	end;
end;

-- reduce garbage janitor works (not allocating every frame)
local _transform_arg = { x = 0, y = 0, };
local _tag_arg       = {};

local pool_len = 0;
local pool_selector = {}; do
	local index = 1;
	local resume = true;

	local function clean_stray()
		-- compensate the imperfection of executing with rule
		pool_len       = 0;
		local tagged   = get_windows({ tag = "bad_apple*", });
		local tagged_n = #tagged;

		local class_count = {};
		local max = 0;
		local majority;
		for i = 1, tagged_n do
			local id = tagged[i].class;
			class_count[id] = (class_count[id] or 0) + 1;
			if (class_count[id] > max) then
				max      = class_count[id];
				majority = id;
			end;
		end;

		for i = 1, tagged_n do
			local v = tagged[i];
			if (v.class == majority) then
				pool_len = pool_len + 1;
				pool_selector[pool_len] = "address:" .. v.address;
			else
				_tag_arg.window = v;
				_tag_arg.tag    = "-bad_apple*";
				dispatch(window_tag(_tag_arg));
			end;
		end;
	end;

	local listener; listener = on_event("window.open", function(window)
		if (t_find(window.tags, "bad_apple*")) then resume = true; end;
	end);

	-- this instead of for loop to try and avoid crashes from batch launching
	local spawner; spawner = cycle(function()
		if (not resume) then return; end;
		if (index > MAX_BOXES) then
			if (listener) then
				listener:remove(); listener = nil;
			end;
			clean_stray();
			return spawner:set_enabled(false);
		end;

		_tag_arg.tag = "+bad_apple";
		execute(LAUNCH, _tag_arg);
		index  = index + 1;
		resume = false;
	end, 4, function() return listener and listener:remove(); end);
end;

local is_hidden = {};
local prev_x, prev_y = {}, {};
local prev_w, prev_h = {}, {};

local function hide(i)
	if (is_hidden[i]) then return; end;

	_tag_arg.window = pool_selector[i];
	_tag_arg.tag = "+ba_hidden";
	dispatch(window_tag(_tag_arg));

	is_hidden[i] = true;
	prev_x[i], prev_y[i] = nil, nil;
	prev_w[i], prev_h[i] = nil, nil;
end;

local frames, frame = {}, {};
local frames_len, frame_len = 0, 0;

local chunks_read = 0;

local LOAD_CHUNKS = 500;
local READ_BYTES  = 4;
local READ_SIZE   = LOAD_CHUNKS * READ_BYTES;
local loader; loader = cycle(function()
	local bulk_chunk = box_file:read(READ_SIZE);
	local bulk_len   = bulk_chunk and #bulk_chunk;
	if (bulk_len and (bulk_len == 0 or bulk_len < READ_SIZE)) then
		-- end of file
		box_file:close();
		print("bad_apple PROG: loaded " .. frames_len .. " frames");

		return loader:set_enabled(false);
	end;

	for i = 1, bulk_len, READ_BYTES do
		if (i + 3 > bulk_len) then break; end;

		local x, y, w, h = bulk_chunk:byte(i, i + 3);
		if (x == 0 and y == 0 and w == 0 and h == 0) then
			-- append frame and reset frame
			frames_len = frames_len + 1;
			frames[frames_len] = frame;

			frame_len = 0;
			frame = {};
		else
			-- append box to frame
			frame_len = frame_len + 1;
			frame[frame_len] = { x * SCALE, y * SCALE, w * SCALE, h * SCALE, };
		end;

		chunks_read = chunks_read + 1;
	end;

	if (chunks_read % 2500 < LOAD_CHUNKS) then
		print("bad_apple PROG: loading... " .. frames_len .. " frames");
	end;
end, 4, function()
	if (box_file) then
		box_file:close();
	end;

	frame  = nil;
	frames = nil;
	print("bad_apple PROG: Loader aborted.");
end);

local watcher; watcher = cycle(function()
	-- starts when `loader` finishes caching frames
	-- and all the windows are opened
	if (loader:is_enabled() or pool_len < MAX_BOXES) then return; end;

	watcher:set_enabled(false);

	dispatch(window_close({ window = "title:bad_progress", }));
	print("bad_apple: starting");

	for i = 1, MAX_BOXES do
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

		cycle(function()
			local elapsed = now() - start_time;
			local target = floor(elapsed * 30) + 1;
			if (target > frame_index) then
				-- sync frame
				frame_index = target;
			end;

			local boxes = frames[frame_index];
			if (not boxes) then return; end;

			local boxes_len = #boxes;
			for i = 1, boxes_len do
				local box    = boxes[i];
				local hidden = is_hidden[i];

				local x, y, w, h   = box[1], box[2], box[3], box[4];
				local size_changed = prev_w[i] ~= w or prev_h[i] ~= h;
				local pos_changed  = prev_x[i] ~= x or prev_y[i] ~= y;

				if (hidden or size_changed or pos_changed) then
					local sel = pool_selector[i];
					if (hidden or size_changed) then
						_transform_arg.window = sel;
						_transform_arg.x, _transform_arg.y = w, h;
						dispatch(window_resize(_transform_arg));

						prev_w[i], prev_h[i] = w, h;
					end;

					if (hidden or size_changed or pos_changed) then
						_transform_arg.window = sel;
						_transform_arg.x, _transform_arg.y = OFFSET_X + x, OFFSET_Y + y;
						dispatch(window_move(_transform_arg));

						prev_x[i], prev_y[i] = x, y;
					end;

					if (hidden) then
						_tag_arg.window = sel;
						_tag_arg.tag    = "-ba_hidden";
						dispatch(window_tag(_tag_arg));

						is_hidden[i] = false;
					end;

					prev[i] = box;
				end;
			end;

			for i = boxes_len + 1, MAX_BOXES do
				if (prev[i]) then
					hide(i); prev[i] = nil;
				end;
			end;
			frame_index = frame_index + 1;

			if (frame_index > frames_len) then
				abort_signal = true;
				-- finished
			end;
		end, (1000 / FPS));
	end, 500);
end, 100);
