return {
	LAUNCH = "~/Projects/hyprbadapple/box", -- window launch command

	-- relative path to current dir
	BOX_PATH   = "baprocess/output/boxes.bin", -- path to the generated bin file
	AUDIO_PATH = "baprocess/badapple.mp3",

	MAX_BOXES = 153, -- the `most boxes` from python
	FPS       = 30, -- 1-30 framerate (sync playback)

	SCALE    = 24, -- scale  -> resolution height / (grid height)
	OFFSET_X = 192, -- center -> [(resolution width) - (grid width * scale)] / 2
	OFFSET_Y = 46, -- depends on your top|bottom bars - can be 0 if you want it to fullscreen
};
