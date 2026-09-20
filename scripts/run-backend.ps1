$root = Split-Path -Parent $PSScriptRoot
Start-Process powershell -ArgumentList '-NoExit','-Command',"cd '$root\backend\event-service'; mvn spring-boot:run"
Start-Process powershell -ArgumentList '-NoExit','-Command',"cd '$root\backend\notification-service'; mvn spring-boot:run"
Start-Process powershell -ArgumentList '-NoExit','-Command',"cd '$root\backend\ot-service'; mvn spring-boot:run"
Start-Process powershell -ArgumentList '-NoExit','-Command',"cd '$root\backend\bff-service'; mvn spring-boot:run"
