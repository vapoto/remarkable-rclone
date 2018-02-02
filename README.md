# reMarkable
Tools for the reMarkable tablet

Please also see the [reMarkable Wiki](http://www.remarkablewiki.com/)

## File-tree installation with systemd-timer
Requirement:
Working installation and config of rclone.

1. Open the file ``file-tree.service`` and adapt the line below to your needs:

   ``ExecStart=</absolute-path/file-tree.sh> -v -s`` 
   
   -v add verbosity (good for testing)
   
   -s calls sync via rclone

2. Open the file ``file-tree.timer`` adapt the line below to your needs:
   
   ``OnBootSec=2min`` calls file-tree.service routine 2 min after the device was booted.

   ``OnUnitActiveSec=30min`` calls the file-tree.service routine whenever 30 min have been passed.

3. Open ``file-tree.sh`` and adapt it to your needs, especially the lines below:
   
   ``RCLONE="</absolute-path>/rclone"`` points to the rclone binary, if not in $PATH absolute path is neccecary.

   ``RCLONE_CONFIG="/home/root/.config/rclone/rclone.conf" ``points to the rclone config file

   ``UPLOAD="<storage-name>:remarkable"`` sync to the <storage-name> defined in rclone into the remarkable folder 

4. Copy ``file-tree.sh`` script and the ``file-tree.service`` as  well as ``file-tree.timer`` to your remarkable tablet via scp. Use the home folder, as this will be persistent across updates 
   ```
   scp file-tree.sh file-tree.service file-tree.timer root@10.11.99.1:~
   ```
5. Log into the remarkable tablet.
   ```
   ssh root@10.11.99.1
   ```
6. Copy ``file-tree.service`` and ``file-tree.timer`` to systemd location and restart the systemd daemon and start the timer, finally enable it for persistent work across reboots. You do *NOT* need to start or enable ``file-tree.service`` as this is called from now on via the timer. However, you could start it to trigger the sync manually (good for debugging).
   ```
   cp file-tree.service file-tree.timer /etc/systemd/system/
   systemctl daemon-reload
   systemctl start file-tree.timer
   systemctl enable file-tree.timer
   ```
7. To check the output of the sync use 
   ```
   journalctl -xn 100 | grep file-tree 
   ```
