#!/bin/bash

echo "What is the file path for your schedule?"
path="Schedule.pdf"

# Paths and filenames
sched_pdf="$path"
sched_txt="Schedule.txt"
sched_ics="Schedule.ics"
build_pdf="Building Abbreviations _ Scheduling.pdf"
build_txt="Building Abbreviations _ Scheduling.txt"

# Arrays for course titles, buildings, and rooms
declare -a course_titles
declare -a building
declare -a room

# Day mapping
declare -A day_map=(["M"]=1 ["T"]=2 ["W"]=3 ["Th"]=4 ["F"]=5)

# Check if schedule PDF exists
if [ ! -f "$sched_pdf" ]; then
    echo "Error: File '$sched_pdf' not found"
    exit 1
fi

# Convert PDFs to text
pdftotext "$sched_pdf" "$sched_txt"
pdftotext "$build_pdf" "$build_txt"

# Extract building codes
declare -a build_codes
while IFS= read -r line; do
    if [[ $line =~ ^Code ]]; then
        codes_part=$(echo "${line#Code }" | xargs)
        build_codes+=($codes_part)
    fi
done <"$build_txt"

# Create a regex pattern from building codes
build_codes_pattern="\\b($(
    IFS="|"
    echo "${build_codes[*]}"
))\\b"

# Start the ICS file
cat >"$sched_ics" <<EOF
BEGIN:VCALENDAR
VERSION:2.0
CALSCALE:GREGORIAN
EOF

# Parse schedule text to extract course titles and event details
title_index=0
location_index=0

while IFS= read -r line; do
    # Identify and store course titles
    if [[ $line =~ ^[A-Z]{3,4}\*[0-9]{4}\*.* ]]; then
        course_titles+=("$line")
        continue
    fi

    # Extract building and room information
    while [[ $line =~ (LEC|LAB|EXAM|Electronic)\ ([A-Z]+|TBD),\ ([^ ]+|TBD) ]]; do
        building+=("${BASH_REMATCH[2]}")
        room+=("${BASH_REMATCH[3]}")
        # Remove the matched portion to process the remaining line
        line="${line#*"${BASH_REMATCH[0]}"}"
    done
done <"$sched_txt"

# Parse events and generate ICS entries
while IFS= read -r line; do
    matches=$(echo "$line" | grep -oE '(LEC|LAB|EXAM)[[:space:]]([MTWThF]+)[[:space:]]([0-9:AMP\ \-]+)[[:space:]]([0-9/]+)[[:space:]]([0-9/]+)')
    if [[ -n "$matches" ]]; then
        while IFS= read -r match; do
            if [[ $match =~ (LEC|LAB|EXAM)[[:space:]]([MTWThF]+)[[:space:]]([0-9:AMP\ \-]+)[[:space:]]([0-9/]+)[[:space:]]([0-9/]+) ]]; then
                event_type="${BASH_REMATCH[1]}"
                days="${BASH_REMATCH[2]}"
                time_range="${BASH_REMATCH[3]}"
                start_date="${BASH_REMATCH[4]}"
                end_date="${BASH_REMATCH[5]}"

                # Parse start and end times
                if [[ $time_range =~ ^([0-9]+:[0-9]+[[:space:]]*[APM]+)[[:space:]]*[-]?[[:space:]]*([0-9]+:[0-9]+[[:space:]]*[APM]+)$ ]]; then
                    start_time="${BASH_REMATCH[1]}"
                    end_time="${BASH_REMATCH[2]}"
                else
                    echo "Error parsing time range: $time_range"
                    continue
                fi

                # Map days to numbers
                event_day_numbers=()
                for ((i = 0; i < ${#days}; i++)); do
                    day="${days:i:1}"
                    [[ $day == "T" && ${days:i+1:1} == "h" ]] && day="Th" && ((i++))
                    event_day_numbers+=("${day_map[$day]}")
                done

                # Iterate through date range
                current_date=$(date -I -d "$start_date")
                while [[ "$current_date" < $(date -I -d "$end_date + 1 day") ]]; do
                    day_of_week=$(date -d "$current_date" +%u)
                    if [[ " ${event_day_numbers[@]} " =~ " $day_of_week " ]]; then
                        dtstart=$(date -d "$current_date $start_time" +"%Y%m%dT%H%M%S")
                        dtend=$(date -d "$current_date $end_time" +"%Y%m%dT%H%M%S")
                        dtstamp=$(date -u +"%Y%m%dT%H%M%SZ")
                        # Add event to ICS file
                        cat >>"$sched_ics" <<EOF
BEGIN:VEVENT
UID:$(openssl rand -hex 16)
DTSTAMP:$dtstamp
DTSTART:$dtstart
DTEND:$dtend
SUMMARY:$event_type for ${course_titles[title_index]}
DESCRIPTION:$event_type session for ${course_titles[title_index]}
LOCATION:${building[location_index]} ${room[location_index]}
END:VEVENT
EOF
                    fi
                    current_date=$(date -I -d "$current_date + 1 day")
                done

                # Increment location index
                ((location_index++))
            fi
        done <<<"$matches"

        # Increment title index after processing all events for this course
        ((title_index++))
    fi
done <"$sched_txt"

# Close the ICS file
echo "END:VCALENDAR" >>"$sched_ics"
echo "ICS file generated at $sched_ics"
