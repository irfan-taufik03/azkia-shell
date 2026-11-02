#!/bin/sh
# External rules helper for bspwm to match window titles and dynamic properties
# Args:
#   $1 = window ID
#   $2 = class name
#   $3 = instance name
#   $4 = intermediate consequences

wid=$1
class=$2
instance=$3
consequences=$4

title=$(xdotool getwindowname "$wid" 2>/dev/null)
if [ -z "$title" ]; then
    title=$(xprop -id "$wid" _NET_WM_NAME 2>/dev/null | cut -d '"' -f 2)
fi

# Title-based matching
case "$title" in
    "Picture-in-Picture"|"Picture in picture")
        echo "state=floating sticky=on layer=above"
        exit 0
        ;;
    "Library")
        case "$class" in
            [Ff]irefox*|[Bb]rave*|[Zz]en*|[Ff]loorp*|[Tt]horium*|[Gg]oogle-chrome*|[Vv]ivaldi*)
                echo "state=floating sticky=on layer=above"
                exit 0
                ;;
        esac
        ;;
    "Settings")
        echo "state=floating follow=on focus=on"
        exit 0
        ;;
    "Window Switcher"|"Task Switcher"|"Azkia Switcher"|"AzkiaWindowSwitcher")
        echo "state=floating layer=above follow=on focus=on border=off"
        exit 0
        ;;
    "Azkia Audio Player")
        echo "state=floating follow=on focus=on"
        exit 0
        ;;
    "Azkia PDF")
        echo "state=tiled follow=on focus=on"
        exit 0
        ;;
    "Lockscreen"|"Azkia Lockscreen"|"Azkia Greeter")
        echo "state=fullscreen layer=above border=off follow=on focus=on"
        exit 0
        ;;
    "Azkia Polkit Authentication"|"Azkia Polkit"|"PolkitDialog")
        echo "state=floating layer=above border=off follow=on focus=on"
        exit 0
        ;;
esac

# Instance-based matching
case "$instance" in
    "zoom_linux_float_video_window")
        echo "state=floating sticky=on layer=above focus=off follow=off"
        exit 0
        ;;
esac

# Class & Zoom specific window handling (prevent annotation / toolbar focus-stealing)
case "$class" in
    [Zz]oom*|zoom)
        case "$title" in
            "AnnoFloatBar"|"Annotation"|"Annotate"|"menu window"|"as_toolbar"|"Sharing toolbar"|*"Toolbar"*|*"toolbar"*)
                echo "state=floating focus=off follow=off sticky=on layer=above"
                exit 0
                ;;
            "zoom_linux_float_video_window")
                echo "state=floating focus=off follow=off sticky=on layer=above"
                exit 0
                ;;
            "Zoom Meeting"*|"Zoom Workplace"*|"Zoom Cloud Meetings"*|"Zoom")
                echo "state=floating follow=on focus=on"
                exit 0
                ;;
        esac
        case "$instance" in
            "zoom_linux_float_video_window"|*"anno"*|*"toolbar"*)
                echo "state=floating focus=off follow=off sticky=on layer=above"
                exit 0
                ;;
        esac
        ;;
esac

