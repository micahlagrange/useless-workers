require('src.soundmanager')

local Audio = {}
local currentBGM
local muted = false

local files = {
    dig = { 'assets/audio/mine1.mp3', 'assets/audio/mine2.mp3', 'assets/audio/mine3.mp3', 'assets/audio/mine4.mp3', 'assets/audio/mine5.mp3' },
    explode = { 'assets/audio/explode1.mp3', 'assets/audio/explode2.mp3', 'assets/audio/explode3.mp3' },
    line = 'assets/audio/line_mine.mp3',
    memo = 'assets/audio/click.mp3',
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
    local file = getFile(name)
    if not file then return nil end
    local ok, src = pcall(love.audio.play, file, 'static', false)
    if ok then return src end
    return nil
end

function Audio.playBGM(name)
    Audio.stopMusic()
    local ok, src = pcall(love.audio.play, files[name], 'stream', true)
    if ok then
        currentBGM = src
        if muted then currentBGM:setVolume(0) end
    end
    return name
end

function Audio.stopMusic()
    if currentBGM then love.audio.stop(currentBGM) end
    currentBGM = nil
end

function Audio.toggleMute()
    muted = not muted
    if currentBGM then currentBGM:setVolume(muted and 0 or 1) end
    return muted
end

function Audio.isMuted()
    return muted
end

function Audio.update(dt)
    love.audio.update()
end

return Audio
