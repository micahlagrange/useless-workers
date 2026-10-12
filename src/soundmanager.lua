do
    local sources = {}

    function love.audio.update()
        if #sources == 0 then return end
        local remove = {}
        for _, s in pairs(sources) do
            if not s:isPlaying() then
                remove[#remove + 1] = s
            end
        end
        for _, s in ipairs(remove) do
            sources[s] = nil
        end
    end

    local play = love.audio.play
    function love.audio.play(what, how, loop)
        local src = what
        if type(what) ~= 'userdata' or not what:typeOf('Source') then
            src = love.audio.newSource(what, how)
            src:setLooping(loop or false)
        else
            return play(src)
        end
        play(src)
        sources[src] = src
        return src
    end

    local stop = love.audio.stop
    function love.audio.stop(src)
        if not src then return end
        stop(src)
        sources[src] = nil
    end
end
