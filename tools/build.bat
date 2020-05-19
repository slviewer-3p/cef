@rem Chromium/CEF build script
@rem 
@rem Copyright 2020, Linden Research, Inc.
@rem Callum Prentice - callum@lindenlab.com
@rem 
@rem Permission is hereby granted, free of charge, to any person obtaining a copy
@rem of this software and associated documentation files [the "Software"], to deal
@rem in the Software without restriction, including without limitation the rights
@rem to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
@rem copies of the Software, and to permit persons to whom the Software is
@rem furnished to do so, subject to the following conditions:

@rem The above copyright notice and this permission notice shall be included in
@rem all copies or substantial portions of the Software.

@rem THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
@rem IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
@rem FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
@rem AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
@rem LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
@rem OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
@rem THE SOFTWARE.

@rem This batch file worked up using instructions from this CEF page:
@rem https://bitbucket.org/chromiumembedded/cef/wiki/MasterBuildQuickStart.md

@rem default values - change via command line parameters - see below
@set DEFAULT_ROOT_CODE_DIRECTORY=\code
@set DEFAULT_BIT_WIDTH=64
@set DEFAULT_PROPRIETARY_CODEC=1
@set DEFAULT_BRANCH=4044
@set DEFAULT_CEF_COMMIT_HASH="b223419"
@set DEFAULT_CEF_DISTRIB_SUBDIR="cef"

@rem This "special" variable expands to the drive letter and path of the batch file it
@rem is referenced from. In this case, we know the de-duping Python script is in the same
@rem folder as this batch file, so we use it to build a path to the script vs forcing
@rem another command line parameter to this batch file.
@set PYTHON_DEDUPE_PATH=%~dp0dedupe_path.py

@rem Pass in the name of the directory where the build happens as param 1 or '-' to use default
@set ROOT_CODE_DIRECTORY=%DEFAULT_ROOT_CODE_DIRECTORY%
@if not [%1]==[] (if not [%1]==[-] (set ROOT_CODE_DIRECTORY=%1))

@rem Pass in bit width [32/64] of the build as param 2 or '-' to use default
@set BIT_WIDTH=%DEFAULT_BIT_WIDTH%
@if not [%2]==[] (if not [%2]==[-] (set BIT_WIDTH=%2))

@rem Pass in 1/0 to enable/disable proprietary codecs as param 3 or '-' to use default
@set PROPRIETARY_CODEC=%DEFAULT_PROPRIETARY_CODEC%
@if not [%3]==[] (if not [%3]==[-] (set PROPRIETARY_CODEC=%3))

@rem Pass in the branch number to build as param 4 or '-' to use default
@set BRANCH=%DEFAULT_BRANCH%
@if not [%4]==[] (if not [%4]==[-] (set BRANCH=%4))

@rem Pass in the commit hash to pull from as param 5 or '-' to use default
@set CEF_COMMIT_HASH=%DEFAULT_CEF_COMMIT_HASH%
@if not [%5]==[] (if not [%5]==[-] (set CEF_COMMIT_HASH=%5))

@rem Pass in the name of the directory where the build happens as param 6 or '-' to use default
@set CEF_DISTRIB_SUBDIR=%DEFAULT_CEF_DISTRIB_SUBDIR%
@if not [%6]==[] ( if not [%6]==[-] (set CEF_DISTRIB_SUBDIR=%6))

@mkdir %ROOT_CODE_DIRECTORY%\automate
@mkdir %ROOT_CODE_DIRECTORY%\chromium_git
@mkdir %ROOT_CODE_DIRECTORY%\depot_tools

@cd %ROOT_CODE_DIRECTORY% 

@rem Chromium/CEF build scripts need this directory in the path
@set PATH=%ROOT_CODE_DIRECTORY%\depot_tools;%PATH%

@rem initialize build_details file
@echo Build details: > %ROOT_CODE_DIRECTORY%\build_details

@rem record build settings
@echo ROOT_CODE_DIRECTORY: %ROOT_CODE_DIRECTORY% >> %ROOT_CODE_DIRECTORY%\build_details
@echo BIT_WIDTH: %BIT_WIDTH% >> %ROOT_CODE_DIRECTORY%\build_details
@echo PROPRIETARY_CODEC: %PROPRIETARY_CODEC% >> %ROOT_CODE_DIRECTORY%\build_details
@echo BRANCH: %BRANCH% >> %ROOT_CODE_DIRECTORY%\build_details
@echo. >> %ROOT_CODE_DIRECTORY%\build_details

@rem rudimentary timing
@echo Start build: >> %ROOT_CODE_DIRECTORY%\build_details
@time /t >> %ROOT_CODE_DIRECTORY%\build_details
@echo. >> %ROOT_CODE_DIRECTORY%\build_details

@rem grab a recent version of the depot tools. Optionally use curl as part of Cygwin 
@rem if we are *NOT* in a Windows 10 environment - otherwise, assume the relevant
@rem Powershell function is present - we used to use Powershell curl.exe but there
@rem were mysterious failures in TeamCity so we adopted this new approach
@ver | findstr "10.0" > nul
@if errorlevel = 1 (
    @curl.exe -O https://storage.googleapis.com/chrome-infra/depot_tools.zip
) else (
    @powershell.exe -NoP -NonI -Command "curl.exe -O https://storage.googleapis.com/chrome-infra/depot_tools.zip"

)

@rem uncompress the zip file - optionally use unzip as part of Cygwin if we are *NOT* in a
@rem Windows 10 environment - otherwise, assume the relevant Powershell function is present
@rem and use it
@ver | findstr "10.0" > nul
@if errorlevel = 1 (
    @unzip depot_tools.zip -d depot_tools 
) else (
    @powershell.exe -NoP -NonI -Command "Expand-Archive 'depot_tools.zip' '.\depot_tools\'"
)

@rem Rudimentary timing
@echo Downloaded and unzipped depot tools build: >> %ROOT_CODE_DIRECTORY%\build_details
@time /t >> %ROOT_CODE_DIRECTORY%\build_details
@echo. >> %ROOT_CODE_DIRECTORY%\build_details

@rem run the Google batch file to update it to latest version via git pull
@cd %ROOT_CODE_DIRECTORY%\depot_tools
@call update_depot_tools.bat

@rem Rudimentary timing
@echo Ran update_depot_tools.bat: >> %ROOT_CODE_DIRECTORY%\build_details
@time /t >> %ROOT_CODE_DIRECTORY%\build_details
@echo. >> %ROOT_CODE_DIRECTORY%\build_details

@rem grab latest version of the main python script
@cd %ROOT_CODE_DIRECTORY%\automate
@powershell.exe -NoP -NonI -Command "curl.exe -O https://bitbucket.org/chromiumembedded/cef/raw/master/tools/automate/automate-git.py"

@rem Starting point for automate-git.py step
@cd %ROOT_CODE_DIRECTORY%\chromium_git

@rem Settings taking from the Chromium/CEF Master Build Page.
@set GN_ARGUMENTS=--ide=vs2017 --sln=cef --filters=//cef/*

@rem Not everyone wants the official media codec support
@set GN_DEFINES=is_official_build=true
@if "%PROPRIETARY_CODEC%"=="1" (set GN_DEFINES=is_official_build=true proprietary_codecs=true ffmpeg_branding=Chrome)

set GYP_MSVS_VERSION=2017

@rem specifiy that the final build result is a .tar.bz2 archive vs zip
@set CEF_ARCHIVE_FORMAT=tar.bz2

@rem Allow building of both 32 and 64 bit versions
@set BUILD_64BIT_FLAGS=
@if "%BIT_WIDTH%"=="64" (set BUILD_64BIT_FLAGS=--x64-build)

@rem Write the original path to the build details file for debugging
@echo. >> %ROOT_CODE_DIRECTORY%\build_details
@echo "Original path is " >> %ROOT_CODE_DIRECTORY%\build_details
@echo %PATH% >> %ROOT_CODE_DIRECTORY%\build_details

@rem This stanza of code calls a Python script that grabs
@rem the PATH, removes dupes and writes it to the file 
@rem given as a parameter to the script. Then a line of 
@rem batch reads the file and sets the PATH from it.
@set DD_PATH_FILE=%ROOT_CODE_DIRECTORY%\dd_path.txt
@python.exe %PYTHON_DEDUPE_PATH% %DD_PATH_FILE%
@for /f "delims=" %%x in (%DD_PATH_FILE%) do set DD_PATH=%%x
@set PATH=%DD_PATH% >> %ROOT_CODE_DIRECTORY%\build_details

@rem Write the de-duplicated path to the build details file for debugging
@echo "Updated path is " >> %ROOT_CODE_DIRECTORY%\build_details
@echo %PATH% >> %ROOT_CODE_DIRECTORY%\build_details
@echo. >> %ROOT_CODE_DIRECTORY%\build_details

@rem Rudimentary timing
@echo About to run automate-git.py: >> %ROOT_CODE_DIRECTORY%\build_details
@time /t >> %ROOT_CODE_DIRECTORY%\build_details
@echo. >> %ROOT_CODE_DIRECTORY%\build_details

@rem The main build script that does all the work. The CEF build wiki pages 
@rem list some other commands [ninja...] but those are only required if
@rem you are editing source and don't want to make a full build each time
cd %ROOT_CODE_DIRECTORY%\chromium_git\chromium\src\cef
@python ..\automate\automate-git.py^
 --download-dir=%ROOT_CODE_DIRECTORY%\chromium_git^
 --depot-tools-dir=%ROOT_CODE_DIRECTORY%\depot_tools^
 --branch=%BRANCH%^
 --client-distrib^
 --distrib-subdir=%CEF_DISTRIB_SUBDIR%^
 --force-clean^
 %BUILD_64BIT_FLAGS%

@rem Rudimentary timing
@echo Ran automate-git.py: >> %ROOT_CODE_DIRECTORY%\build_details
@time /t >> %ROOT_CODE_DIRECTORY%\build_details
@echo. >> %ROOT_CODE_DIRECTORY%\build_details

@rem Rudimentary timing
@cd %ROOT_CODE_DIRECTORY%
@echo Build start and end times:
@echo End build: >> %ROOT_CODE_DIRECTORY%\build_details
@time /t >> %ROOT_CODE_DIRECTORY%\build_details
@echo. >> %ROOT_CODE_DIRECTORY%\build_details
@type %ROOT_CODE_DIRECTORY%\build_details

@echo.
@echo If all went well, zipped builds will be in %ROOT_CODE_DIRECTORY%\chromium_git\chromium\src\cef\binary_distrib
@echo.

:end