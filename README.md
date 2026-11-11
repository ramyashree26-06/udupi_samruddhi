UDUPI SAMRUDDHI BILLING (v9) - all 17 tabs

Easiest: double-click run_billing.bat (on the Desktop).
Or in PowerShell:  cd %USERPROFILE%\Documents\hotel_billing  then  flutter pub get  then  flutter run -d windows

Tabs: Dashboard, POS Billing, Table Management, Orders & Bills, Kitchen Display, Menu Management,
Inventory & Stock, Purchases, Suppliers, Customers, Expenses, Staff & Users, Sales Reports,
GST Reports, Settings, User Permissions, Backup & Restore.

Staff PIN: if you set a PIN for any staff, the app asks for it at start.
Forgot the PIN? Create an empty file  Documents\HotelBilling\reset_pin.txt  and open the app: PINs are cleared.
Data is saved in Documents\HotelBilling (backups in the Backups folder).

## Android app (phone and tablet)
Same app, same screens, own data on each device. Inventory is not shown on Android.

Build the APK (once, then again after any change):
1. Double-click `build_android.bat`  (first run adds the Android part, then builds).
2. When it says DONE, copy `Hotel_Billing.apk` to the phone/tablet (WhatsApp, USB or Drive) and tap it to install.

Notes
- Printing on Android opens the phone's print dialog. A Wi-Fi receipt printer by IP (Settings > Printer) also works.
- Backups stay inside the app. Backup screen > Share saves a copy outside the phone.
- Waiter role (was Kitchen): POS, Tables and Kitchen screen.
