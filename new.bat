@echo off
git config --global user.email "223996272+SupportAquafeb@users.noreply.github.com"
git config --global user.name "support@aquafeb.com"
git commit --amend --reset-author
git push -u origin main

pause