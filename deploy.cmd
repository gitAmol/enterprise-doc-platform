@echo off
REM ============================================================================
REM Enterprise Document Platform - Deployment Script
REM ============================================================================

echo.
echo ========================================
echo Enterprise Document Platform Deployment
echo ========================================
echo.

REM Check if Azure CLI is installed
where az >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Azure CLI is not installed. Please install from https://aka.ms/installazurecli
    exit /b 1
)

REM Check if logged in
az account show >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [INFO] Not logged in. Starting Azure login...
    az login
)

REM Display current subscription
echo.
echo [INFO] Current subscription:
az account show --query "{Name:name, SubscriptionId:id}" --output table

echo.
set /p CONFIRM="Do you want to deploy to this subscription? (y/n): "
if /i not "%CONFIRM%"=="y" (
    echo [INFO] Deployment cancelled.
    exit /b 0
)

REM Set variables
set LOCATION=eastus
set TEMPLATE_FILE=infra\main.bicep
set PARAMETERS_FILE=infra\parameters.dev.json

echo.
echo [INFO] Validating Bicep template...
az bicep build --file %TEMPLATE_FILE%
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Bicep validation failed.
    exit /b 1
)

echo.
echo [INFO] Starting deployment...
echo [INFO] Location: %LOCATION%
echo [INFO] Template: %TEMPLATE_FILE%
echo [INFO] Parameters: %PARAMETERS_FILE%
echo.

az deployment sub create ^
    --location %LOCATION% ^
    --template-file %TEMPLATE_FILE% ^
    --parameters %PARAMETERS_FILE% ^
    --name "docplatform-deployment-%date:~-4,4%%date:~-10,2%%date:~-7,2%"

if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Deployment failed!
    exit /b 1
)

echo.
echo ========================================
echo Deployment completed successfully!
echo ========================================
echo.
echo [INFO] View resources in Azure Portal:
echo https://portal.azure.com/#@/resource/subscriptions

pause
