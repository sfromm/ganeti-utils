#!/usr/bin/python

# Written by Stephen Fromm <sfromm nero net>
# (C) 2011-2012 University of Oregon
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA.

import json
import os
import re
import sys
import time
import urllib2

GNT_RAPI_URL = "https://localhost:5080/2/info"
STATUS_FILE = "/var/run/gnt-cluster-verify-status"
MAX_AGE = 1200

def _exit_state(val):
    print "%s" % (val)
    sys.exit(0)

def read_status_file():
    status = open(STATUS_FILE, 'r').readline().rstrip()
    return status

def get_node_name():
    return os.uname()[1]

def get_gnt_master():
    name = ""
    try:
        f = urllib2.urlopen(GNT_RAPI_URL)
        info = json.loads(f.read())
        name = info['master']
    except urllib2.URLError as e:
        name = ""
    return name

def verify_status_file_last_mod():
    mtime = os.path.getmtime(STATUS_FILE)
    now = time.time()
    delta = now - mtime
    if delta > MAX_AGE:
        return False
    else:
        return True

def verify_status_file_content(status):
    return re.match("^[0-9]+$", status)

def main():
    if get_gnt_master() != get_node_name():
        _exit_state(0)
    if not os.path.exists(STATUS_FILE):
        _exit_state(1)
    if not verify_status_file_last_mod():
        _exit_state(2)
    status = read_status_file()
    if not verify_status_file_content(status):
        _exit_state(3)
    _exit_state(status)

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt as e:
        print >> sys.stderr, "Exiting on user request"
        sys.exit(1)
