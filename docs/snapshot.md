# Snapshot ISO with the latest changes

The ISO carries what is installed on the build host, not the repo. To build a reset ISO with the newest menu, panels and tools:

1. `git pull` in `mabox-noctalia-ce`.
2. `./install.sh`. It builds the working tree and installs it.
3. Check the install: `tests/iso-check.sh --host`. Build only when it prints `ok:`; exit code 2 means a tool is missing, not a wrong install.
4. Build the snapshot: `mabox-snapshot create reset`, or use the Snapshot panel.
   After a build in the panel, the terminal offers `mb-iso-next`: write the ISO to USB or start it in a VM (quickbox-qt 1.4 or newer). The panel's USB view has the same `USB` and `VM` buttons per ISO.
5. Check the image: `tests/iso-check.sh <workdir>/iso/mabox/x86_64/rootfs.sfs`. It lists every checked file that is missing or differs in the image.

`mb-plugins-enable` enables each Mabox plugin once for a user, on login. The plugins it has handled are in `~/.local/state/mabox-noctalia-ce/plugins-seen`: delete a line to get that plugin enabled again.
