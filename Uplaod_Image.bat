@echo off
chcp 65001
cd /d C:\Users\Public\AQVercelProject

echo.
echo ================================================
echo.
echo 開始執行圖片上傳...
git add -A
git commit -m "圖片" >nul 2>&1
git push -u origin main >nul 2>&1

echo.
echo ================================================
echo.
echo 圖片上傳完成 ( 現在時間 %TIME%)
echo.
echo 等待五分鐘後即可確認圖片URL...
echo.

echo ================================================
echo.
echo 1分鐘後將自動關閉視窗...
timeout /t 60 >nul
exit