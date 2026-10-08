#!/bin/sh
# Local development access deliberately enabled in this owner-test image.
printf '\nFedora Rawhide on Uke — local development terminal\n'
printf 'Kernel: '; uname -r
printf 'Root: '; findmnt -n -o SOURCE,FSTYPE /
printf 'This shell is on the linux partition.\n\n'
export PS1='Fedora Uke:\w# '
exec /usr/bin/bash --noprofile --norc -i
