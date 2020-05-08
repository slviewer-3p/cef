# This script grabs the current system PATH variable and removes duplicate
# entries but importantly, retains the same order of each directory.
# The de-duped list is then wirtten to a file - default of the first argument.

# This script is used when building the Windows 32/64 version of Chromium/CEF
# inside the Linden autobuild environment where some sequence of events,
# as yet undiscovered, causes the directory entries in the PATH to be
# duplicated multiple times. The maximum length of the PATH variable in 
# Windows is 8191 bytes and if the path gets longer than that, running
# commands from directories listed in the PATH will fail with a cryptic
# "Line too long" message. This de-duping process is used to reset the path
# periodically and appears to solve the issue until the root cause is determined.

import os
from collections import OrderedDict
import sys

if len(sys.argv) != 2:
    output_path = ".\\path.txt"
else:
    output_path = sys.argv[1]

cur_path = os.getenv("PATH")
deduped_path = os.pathsep.join(OrderedDict((dir.rstrip(r'\/'), 1) for dir in cur_path.split(os.pathsep)))

with open(output_path, 'w') as output_file:
    output_file.write(deduped_path)
