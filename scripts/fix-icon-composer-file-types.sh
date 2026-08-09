#!/bin/sh

set -eu

project_file="OpenCodeIOSClient.xcodeproj/project.pbxproj"

if [ ! -f "$project_file" ]; then
    echo "error: Missing $project_file"
    exit 1
fi

/usr/bin/perl -0pi -e 's/lastKnownFileType = wrapper\.icon;/lastKnownFileType = folder.iconcomposer.icon;/g' "$project_file"
