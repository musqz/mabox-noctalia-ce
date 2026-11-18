# Snapshot ISO

Build an ISO of your system with the Snapshot panel (`mabox-snapshot`). Open it from the root menu → Mabox noctalia ce → Snapshot, or `/mb snapshot` in the launcher.

<p align="center"><a href="img/snapshot-panel.png"><img src="img/thumb/snapshot-panel.png" alt="Snapshot panel" style="margin: 8px"></a> <a href="img/snapshot-isos.png"><img src="img/thumb/snapshot-isos.png" alt="ISO list with USB and VM buttons" style="margin: 8px"></a></p>

1. Pick the kernels for the ISO at the top.
2. Pick a profile: *Share with others* (clean copy, login demo/demo), *Personal snapshot* (full clone with your files and passwords, keep it private), *Smallest ISO* or *Quick test build*.
3. *Explain* shows what the profile does. *Build* runs it in a terminal and asks for your sudo password.
4. *ISO list* shows the finished ISOs. *USB* writes one to a stick (this erases the stick and adds a persistence partition). *VM* starts it in quickbox-qt. The trash button deletes the ISO.
5. *Exclude list* shows what stays out of the ISO. Type a path from the root (for example `home/*/Downloads`) or pick a folder with the folder button, then press *Add*; the trash button removes a line. Under *Keep a path inside an excluded folder*, exclude a folder and include a path inside it (exclude `home/*/Documents`, include `home/*/Documents/Enpass`). Every change asks for your password in the Noctalia prompt, because the lists live in `/etc/mabox-snapshot`.
