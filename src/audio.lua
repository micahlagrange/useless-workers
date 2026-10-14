require('src.soundmanager')

local Audio = {}
local currentBGM
local muted = false

-- The mixer: music, effects, and alerts (the sounds that want the player's
-- attention). Each from 0 to 1, kept between runs in volume.txt.
Audio.CHANNELS = { 'music', 'sfx', 'alert' }
local volumes = { music = 1, sfx = 1, alert = 1 }
local ALERTS = { complain = true, quit = true, report = true, win = true, hire = true }
local VOLUME_FILE = 'volume.txt'

local files = {
    dig = { 'assets/audio/mine1.mp3', 'assets/audio/mine2.mp3', 'assets/audio/mine3.mp3', 'assets/audio/mine4.mp3', 'assets/audio/mine5.mp3' },
    explode = { 'assets/audio/explode1.mp3', 'assets/audio/explode2.mp3', 'assets/audio/explode3.mp3' },
    line = 'assets/audio/line_mine.mp3',
    complain = 'assets/audio/tension1.mp3',
    eat = { 'assets/audio/crunch.mp3', 'assets/audio/crunch2.mp3', 'assets/audio/slurp.mp3' },
    deliver = { 'assets/audio/doot1.mp3', 'assets/audio/doot23.mp3' },
    quit = 'assets/audio/quick_blips.mp3',
    hire = 'assets/audio/settled.mp3',
    report = 'assets/audio/success.mp3',
    win = 'assets/audio/win.mp3',
    click = 'assets/audio/click.mp3',
    theme = 'assets/audio/theme.wav',
}

local idx = 1
local function getFile(name)
    local entry = files[name]
    if type(entry) == 'table' then
        local file = entry[idx % #entry + 1]
        idx = idx + 1
        if idx > 10000 then idx = 1 end
        return file
    end
    return entry
end

function Audio.playSFX(name)
    if muted then return nil end
    local volume = volumes[ALERTS[name] and 'alert' or 'sfx']
    if volume <= 0 then return nil end
    local file = getFile(name)
    if not file then return nil end
    local ok, src = pcall(love.audio.play, file, 'static', false)
    if ok then
        if src and src.setVolume then src:setVolume(volume) end
        return src
    end
    return nil
end

local function applyMusicVolume()
    if currentBGM then currentBGM:setVolume(muted and 0 or volumes.music) end
end

function Audio.getVolume(channel)
    return volumes[channel]
end

-- Set one channel, in tenths, and remember it.
function Audio.setVolume(channel, v)
    if volumes[channel] == nil then return end
    volumes[channel] = math.floor(math.max(0, math.min(1, v)) * 10 + 0.5) / 10
    applyMusicVolume()
    if love.filesystem and love.filesystem.write then
        local lines = {}
        for _, c in ipairs(Audio.CHANNELS) do lines[#lines + 1] = c .. '=' .. volumes[c] end
        pcall(love.filesystem.write, VOLUME_FILE, table.concat(lines, '\n'))
    end
end

function Audio.loadVolumes()
    if not (love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(VOLUME_FILE)) then return end
    local ok, data = pcall(love.filesystem.read, VOLUME_FILE)
    if not ok or type(data) ~= 'string' then return end
    for c, v in data:gmatch('(%a+)=([%d%.]+)') do
        if volumes[c] ~= nil then volumes[c] = math.max(0, math.min(1, tonumber(v) or 1)) end
    end
    applyMusicVolume()
end

function Audio.playBGM(name)
    Audio.stopMusic()
    local ok, src = pcall(love.audio.play, files[name], 'stream', true)
    if ok then
        currentBGM = src
        applyMusicVolume()
    end
    return name
end

function Audio.stopMusic()
    if currentBGM then love.audio.stop(currentBGM) end
    currentBGM = nil
end

function Audio.toggleMute()
    muted = not muted
    applyMusicVolume()
    return muted
end

function Audio.isMuted()
    return muted
end

function Audio.update(dt)
    love.audio.update()
end

return Audio
