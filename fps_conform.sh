#!/bin/bash

FFMPEG_PATH="C:/ffmpeg/bin/ffmpeg.exe"
FFPROBE_PATH="C:/ffmpeg/bin/ffprobe.exe"
MEDIAINFO_PATH="C:/ffmpeg/mediainfo/MediaInfo.exe"
MKVMERGE_PATH="C:/Program Files/MKVToolNix/mkvmerge.exe"
#AUDIO_CODEC="-c:a libopus -b:a 128k"
AUDIO_CODEC="-c:a libfdk_aac -b:a 192k"

# Current directory script is being executed from
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Check if cygpath is available (indicates we're in Cygwin or a compatible environment)
if command -v cygpath >/dev/null 2>&1; then
  # Convert to Windows-style path
  DIR=$(cygpath -w "$DIR")
fi

# Folder parameter
FOLDER="$1"

# FPS parameter
FPS="$2"

USAGE="USAGE: bash fps_conform.sh [folder] [framerate]\n  [folder] = location of video files to be converted\n  [framerate] = framerate to conform to (23.976, 24, 25)"

if [[ $# == 0 ]]; then
  echo -e "$USAGE"
  exit 1
fi

# Checking for valid first parameter
if [[ ! -d "$FOLDER" ]]; then
  echo "[ERROR] Please provide a valid folder!"
  echo -e "$USAGE"
  exit 1
fi

# Checking for valid second parameter
if [[ "$FPS" != "23.976" && "$FPS" != "24" && "$FPS" != "25" ]]; then
  echo -e "[ERROR] Please provide the framerate to conform to!\n        Valid options: 23.976, 24, 25"
  echo -e "$USAGE"
  exit 1
fi

# Setting output directory based on FPS
OUTPUT_VID="$DIR/temp/vid_$FPS"
OUTPUT_AUD="$DIR/temp/aud_$FPS"
OUTPUT_SUB="$DIR/temp/sub_$FPS"
OUTPUT_MUX="$DIR/temp/mux_$FPS"

# Making output directories
mkdir -p "$OUTPUT_VID"
mkdir -p "$OUTPUT_AUD"
mkdir -p "$OUTPUT_SUB"
mkdir -p "$OUTPUT_MUX"

MSG_ERROR=" ➥ [ERROR ]"
MSG_NOTICE=" ➥ [NOTICE]"

# Convert video to desired FPS using mkvmerge
function CONVERT_VID () {
  echo "$MSG_NOTICE Starting video conversion"

  # Get index of video track
  VID_INDEX=$("$FFPROBE_PATH" -v error -of default=noprint_wrappers=1:nokey=1 -select_streams v:0 -show_entries stream=index "$1")

  # Alternate for weird-ass files
  # "$MKVMERGE_PATH" -q -o "$OUTPUT_VID/$OUTPUT_FILE" --sync "0:0,25/24" -d "$VID_INDEX" -A -S -T "$1" 2>"$OUTPUT_VID/$OUTPUT_FILE.err"

  "$MKVMERGE_PATH" -q -o "$OUTPUT_VID/$OUTPUT_FILE" --default-duration "$VID_INDEX:$FPS_OUT" -d "$VID_INDEX" -A -S -T "$1" 2>"$OUTPUT_VID/$OUTPUT_FILE.err"
}

# Convert audio to desired length, compensating pitch
function CONVERT_AUD () {
  echo "$MSG_NOTICE Starting audio conversion"
  local channels
  local layout

  channels=$("$FFPROBE_PATH" -show_entries stream=channels -select_streams a:0 -of compact=p=0:nk=1 -v 0 "$1")

  if [[ "$channels" == "8" ]]; then
    layout="7.1"
  elif [[ "$channels" == "6" ]]; then
    layout="5.1"
  else
    layout="stereo"
  fi

  "$FFMPEG_PATH" -y -v error -i "$1" $AUDIO_CODEC -filter:a "atempo=$TEMPO,aformat=channel_layouts=$layout" -vn "$OUTPUT_AUD/$OUTPUT_FILE" 2>"$OUTPUT_AUD/$OUTPUT_FILE.err"
}

# Convert subtitles to desired length
function CONVERT_SUB () {
  echo "$MSG_NOTICE Starting subtitle conversion"

  # Get subtitle language
  SUBTITLE_LANG=$("$FFPROBE_PATH" -v error -of default=noprint_wrappers=1:nokey=1 -select_streams s:0 -show_entries stream_tags=language "$1")

  # Extract subtitle file if necessary, perform FPS change
  if [[ ! -s "$SUBTITLE_EXT" ]]; then
    echo "$MSG_NOTICE Using embedded subtitles"
    "$FFMPEG_PATH" -y -v error -i "$1" -map 0:s:0 "$OUTPUT_SUB/${OUTPUT_FILE}_original.srt"
    perl "$DIR/srt/srtshift.pl" "${FPS_IN}-${FPS}" "${OUTPUT_SUB}/${OUTPUT_FILE}_original.srt" "${OUTPUT_SUB}/$OUTPUT_FILE" > "$DIR"/temp/perl.log 2>&1
  else
    echo "$MSG_NOTICE Using external subtitles"
    perl "$DIR/srt/srtshift.pl" "${FPS_IN}-${FPS}" "$SUBTITLE_EXT" "${OUTPUT_SUB}/${OUTPUT_FILE}" > "$DIR"/temp/perl.log 2>&1
  fi

}

function MUX () {
  echo "$MSG_NOTICE Starting muxing"
  if [[ "$SUBTITLE_TYPE" == "srt" || "$SUBTITLE_TYPE" == "subrip" && -n "$SUBTITLE_LANG" ]]; then
    "$FFMPEG_PATH" -y -v error -i "$OUTPUT_VID/$OUTPUT_FILE" -i "$OUTPUT_AUD/$OUTPUT_FILE" -i "$OUTPUT_SUB/$OUTPUT_FILE" -c copy -map 0:v:0 -map 1:a:0 -map 2:s:0 -metadata:s:2 language="$SUBTITLE_LANG" "$OUTPUT_MUX/$OUTPUT_FILE" 2>"$OUTPUT_MUX/$OUTPUT_FILE.err"
  elif [[ "$SUBTITLE_TYPE" == "srt" || "$SUBTITLE_TYPE" == "subrip" ]]; then
    "$FFMPEG_PATH" -y -v error -i "$OUTPUT_VID/$OUTPUT_FILE" -i "$OUTPUT_AUD/$OUTPUT_FILE" -i "$OUTPUT_SUB/$OUTPUT_FILE" -c copy -map 0:v:0 -map 1:a:0 -map 2:s:0 "$OUTPUT_MUX/$OUTPUT_FILE" 2>"$OUTPUT_MUX/$OUTPUT_FILE.err"
  elif [[ -s "$SUBTITLE_EXT" ]]; then
    "$FFMPEG_PATH" -y -v error -i "$OUTPUT_VID/$OUTPUT_FILE" -i "$OUTPUT_AUD/$OUTPUT_FILE" -i "$OUTPUT_SUB/$OUTPUT_FILE" -c copy -map 0:v:0 -map 1:a:0 -map 2:s:0 "$OUTPUT_MUX/$OUTPUT_FILE" 2>"$OUTPUT_MUX/$OUTPUT_FILE.err"
  else
    "$FFMPEG_PATH" -y -v error -i "$OUTPUT_VID/$OUTPUT_FILE" -i "$OUTPUT_AUD/$OUTPUT_FILE" -c copy -map 0:v:0 -map 1:a:0 "$OUTPUT_MUX/$OUTPUT_FILE" 2>"$OUTPUT_MUX/$OUTPUT_FILE.err"
  fi
}

# Loop to convert all files with mkv extension in current directory
echo "PROCESSING $FOLDER" > fps_error.log
mapfile -d '' -t files < <(find "$FOLDER" -type f \( -iname "*.mp4" -o -iname "*.mkv" \) -print0)
for INPUT_FILE in "${files[@]}"; do
  echo "FILE: $INPUT_FILE"

  # Get basename of file
  OUTPUT_FILE=$(basename "$INPUT_FILE")

  # Get framerate of input file to make calculate conversion
  FPS_IN=$("$MEDIAINFO_PATH" --Inform="Video;%FrameRate_Num%/%FrameRate_Den%" "$INPUT_FILE")
  if [[ "$FPS_IN" == "/" ]]; then
    FPS_IN=$("$MEDIAINFO_PATH" --Inform="Video;%FrameRate%" "$INPUT_FILE")
  fi

  # Check if there are subtitles embedded and if so what type
  SUBTITLE_TYPE=$("$FFPROBE_PATH" -v error -of default=noprint_wrappers=1:nokey=1 -select_streams s:0 -show_entries stream=codec_name "$INPUT_FILE")

  # Check for external subtitles if there are none embedded
  if [[ -z "$SUBTITLE_TYPE" ]]; then
    SUBTITLE_EXT=$(printf '%s' "$(dirname "$INPUT_FILE")" && printf '/' && printf '%s' "$(basename "$INPUT_FILE" .mkv)" && printf .srt)
  fi

  # Error for same input and output FPS
  ERR_NO_ACTION="$MSG_NOTICE Taking no action, FPS would be unchanged or is unsupported"

  # Error for unsupported framerate
  ERR_UNSUPPORTED="$MSG_ERROR Framerate not supported: $FPS_IN"

  # By default take action
  PASS="false"

  # Determine action, tempo
  if [[ "$FPS_IN" == "24000/1001" || "$FPS_IN" == "23976/1000" || "$FPS_IN" == "23.976" ]]; then
    FPS_IN="23.976"
    if [[ "$FPS" == "25" ]]; then
      FPS_OUT="25p"
      TEMPO="1.042709376"
      echo "$MSG_NOTICE Converting from ${FPS_IN}fps to ${FPS}fps"
    else
      echo -e "$ERR_NO_ACTION"
      PASS="true"
    fi
  elif [[ "$FPS_IN" == "24/1" ]]; then
    FPS_IN="24"
    if [[ "$FPS" == "25" ]]; then
      FPS_OUT="25p"
      TEMPO="1.041666667"
      echo "$MSG_NOTICE Converting from ${FPS_IN}fps to ${FPS}fps"
    else
      echo -e "$ERR_NO_ACTION"
      PASS="true"
    fi
  elif [[ "$FPS_IN" == "25/1" ]]; then
    FPS_IN="25"
    if [[ "$FPS" == "24" ]]; then
      FPS_OUT="24p"
      TEMPO="0.96"
      echo "$MSG_NOTICE Converting from ${FPS_IN}fps to ${FPS}fps"
    elif [[ "$FPS" == "23.976" ]]; then
      FPS_OUT="24000/1001p"
      TEMPO="0.95904"
      echo "$MSG_NOTICE Converting from ${FPS_IN}fps to ${FPS}fps"
    else
      echo -e "$ERR_NO_ACTION"
      PASS="true"
    fi
  else
    echo "$ERR_UNSUPPORTED"
    echo "$INPUT_FILE $ERR_UNSUPPORTED" >> fps_error.log
    PASS="true"
  fi

  # Do conversion for files not set to pass
  if [[ "$PASS" != "true" ]]; then
    CONVERT_VID "$INPUT_FILE"
    if [ -s "$OUTPUT_VID/$OUTPUT_FILE.err" ]; then
      echo -n "$MSG_ERROR During video extraction: "
      cat "$OUTPUT_VID/$OUTPUT_FILE.err"
      echo ""
      echo -n "$INPUT_FILE $MSG_ERROR During video extraction: " >> fps_error.log
      cat "$OUTPUT_VID/$OUTPUT_FILE.err" >> fps_error.log
      echo "" >> fps_error.log
      rm -f "$OUTPUT_VID/$OUTPUT_FILE.err"
      rm -f "$OUTPUT_VID/$OUTPUT_FILE"
      continue
    fi
    rm -f "$OUTPUT_VID/$OUTPUT_FILE.err"
    CONVERT_AUD "$INPUT_FILE"
    if grep -Ev 'facs_q|Last message repeated' "$OUTPUT_AUD/$OUTPUT_FILE.err" | grep -q '.'; then
      echo -n "$MSG_ERROR During audio conversion: "
      cat "$OUTPUT_AUD/$OUTPUT_FILE.err"
      echo ""
      echo -n "$INPUT_FILE $MSG_ERROR During audio conversion: " >> fps_error.log
      cat "$OUTPUT_AUD/$OUTPUT_FILE.err" >> fps_error.log
      echo "" >> fps_error.log
      rm -f "$OUTPUT_AUD/$OUTPUT_FILE.err"
      rm -f "$OUTPUT_VID/$OUTPUT_FILE"
      rm -f "$OUTPUT_AUD/$OUTPUT_FILE"      
      continue
    fi
    rm -f "$OUTPUT_AUD/$OUTPUT_FILE.err"
    if [[ "$SUBTITLE_TYPE" == "srt" || "$SUBTITLE_TYPE" == "subrip" || -s "$SUBTITLE_EXT" ]]; then
      CONVERT_SUB "$INPUT_FILE"
    else
      echo "$MSG_NOTICE No SRT subtitles found"
    fi
    MUX "$INPUT_FILE"
    if [ -s "$OUTPUT_MUX/$OUTPUT_FILE.err" ]; then
      echo -n "$MSG_ERROR During mux: "
      cat "$OUTPUT_MUX/$OUTPUT_FILE.err"
      echo ""
      echo -n "$INPUT_FILE $MSG_ERROR During mux: " >> fps_error.log
      cat "$OUTPUT_MUX/$OUTPUT_FILE.err" >> fps_error.log
      echo "" >> fps_error.log
      rm -f "$OUTPUT_MUX/$OUTPUT_FILE.err"
      rm -f "$OUTPUT_MUX/$OUTPUT_FILE"
      rm -f "$OUTPUT_VID/$OUTPUT_FILE"
      rm -f "$OUTPUT_AUD/$OUTPUT_FILE" 
      continue
    fi
    rm -f "$OUTPUT_MUX/$OUTPUT_FILE.err"

    # Delete intermediary files to save space
    rm -f "$OUTPUT_VID/$OUTPUT_FILE"
    rm -f "$OUTPUT_AUD/$OUTPUT_FILE"

    # Finally, replace the input file with the converted one
    mv -f "$OUTPUT_MUX/$OUTPUT_FILE" "$INPUT_FILE"
    if [ $? -ne 0 ]; then
      echo "MV FAILED $INPUT_FILE" >> fps_error.log
    else
      echo "CONVERTED $INPUT_FILE" >> fps_error.log
    fi
  else
    echo "SKIPPED $INPUT_FILE" >> fps_error.log
  fi
done

# Clean up
rm -rf "$DIR/temp"
