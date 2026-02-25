-- Speech-to-text dictation toggle (Cmd+Option+Z)
-- Copy this file to ~/.hammerspoon/init.lua

require("hs.ipc")

local DICTATE_SCRIPT = os.getenv("HOME") .. "/Projects/rough-riding/dictate.sh"

local isRecording = false
local menuBar = nil
local taskRef = nil  -- prevent GC of async tasks

-- Menu bar icons (Unicode)
local MIC_IDLE = "🎙"
local MIC_RECORDING = "🔴"

local function setupMenuBar()
    menuBar = hs.menubar.new()
    menuBar:setTitle(MIC_IDLE)
    menuBar:setTooltip("Dictation (Cmd+Option+Z)")
end

local function updateMenuBar()
    if menuBar then
        if isRecording then
            menuBar:setTitle(MIC_RECORDING)
        else
            menuBar:setTitle(MIC_IDLE)
        end
    end
end

local function toggleDictation()
    if isRecording then
        -- Stop recording: run stop, then update UI when done
        isRecording = false
        updateMenuBar()
        taskRef = hs.task.new("/bin/bash", function(exitCode, stdOut, stdErr)
            if exitCode ~= 0 then
                hs.alert.show("Dictation error")
                print("dictate.sh stop error: " .. (stdErr or ""))
            end
            taskRef = nil
        end, {DICTATE_SCRIPT, "stop"})
        taskRef:start()
    else
        -- Start recording
        taskRef = hs.task.new("/bin/bash", function(exitCode, stdOut, stdErr)
            if exitCode ~= 0 then
                hs.alert.show("Recording failed to start")
                isRecording = false
                updateMenuBar()
                print("dictate.sh start error: " .. (stdErr or ""))
            end
            taskRef = nil
        end, {DICTATE_SCRIPT, "start"})
        taskRef:start()
        isRecording = true
        updateMenuBar()
    end
end

-- Set up menu bar
setupMenuBar()

-- Bind Cmd+Option+Z
hs.hotkey.bind({"cmd", "alt"}, "Z", toggleDictation)

hs.alert.show("Dictation loaded (Cmd+Option+Z)")
