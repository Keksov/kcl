source /c/projects/kkbot/kbool/kcl/tstringhelper/tstringhelper.sh
echo "LANG=$LANG LC_ALL=$LC_ALL LC_CTYPE=$LC_CTYPE"
echo "length 日本 -> $(string.length '日本'); toUpper café -> $(string.toUpper 'café'); toLower ÄÖ -> $(string.toLower 'ÄÖ'); indexOf 'мир' 'р' -> $(string.indexOf 'мир' 'р'); substring 'мир' 1 -> $(string.substring 'мир' 1); chars 'мир' 1 -> $(string.chars 'мир' 1)"
