#!/bin/bash
# prints "OX OY W H" of the device screen inside the Simulator window
osascript <<'AS'
tell application "Simulator" to activate
delay 0.3
tell application "System Events" to tell process "Simulator"
  set els to UI elements of front window
  repeat with e in els
    set s to size of e
    set w to item 1 of s
    set h to item 2 of s
    if w > 200 and h > 400 then
      set p to position of e
      return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & (w as text) & " " & (h as text)
    end if
  end repeat
end tell
AS
