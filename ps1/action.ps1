param(
    [string]$DestinationLinuxServer,
    [string]$PrivateKeyPath,
    [string]$SudoPassword 
)

# Prompt the user for each parameter if not provided
if (-not $DestinationLinuxServer) {
    $DestinationLinuxServer = Read-Host -Prompt "Enter the destination Linux server (Default: ips1@ubuntu-server)"
    if ([string]::IsNullOrEmpty($DestinationLinuxServer)) {
        $DestinationLinuxServer = "ips1@ubuntu-server"
    }
}

if (-not $PrivateKeyPath) {
    $PrivateKeyPath = Read-Host -Prompt "Enter the private key path (Default: C:\Users\Administrator\Desktop\id_rsa)"
    if ([string]::IsNullOrEmpty($PrivateKeyPath)) {
        $PrivateKeyPath = "C:\Users\Administrator\Desktop\id_rsa"
    }
}

if (-not $SudoPassword) {
    $SudoPassword = Read-Host -Prompt "Enter the sudo password"
}

#extract username from ssh input for home directory
if ($DestinationLinuxServer -match '^([^@]+)@') {
    $user = $matches[1]
}
else {
    Write-Host "Error: No match found for the given username." -ForegroundColor Red
    Start-Sleep -Seconds 1
    exit
}

# Prompt user for source domain to be transferred
$directoryPath = "C:\SmarterMail\Domains"
$subdirectories = Get-ChildItem -Path $directoryPath -Directory
while ($true) {
    $counter = 1
    foreach ($subdir in $subdirectories) {
        Write-Host "$counter. $($subdir.Name)" -ForegroundColor Magenta
        $counter++
    }
    $userSelection = Read-Host -Prompt "Please select a number corresponding to a subdirectory"

    [int]$userSelection

    if ($userSelection -ge 1 -and $userSelection -le $subdirectories.Count) {
        $selectedSubdir = $subdirectories[$userSelection - 1].Name
        Write-Host "You selected " -NoNewline
        Write-Host "$selectedSubdir " -ForegroundColor Magenta  -NoNewline
        Write-Host "Confirm selection? [Y/n] " -NoNewline
        $confirmation = Read-Host
        if ([string]::IsNullOrEmpty($confirmation)) {
            $confirmation = "Y"
        }
        if ($confirmation -eq "Y") {
            Write-Host "Selection confirmed. You selected: $selectedSubdir" -ForegroundColor Green
            $SelectedDomain = $selectedSubdir
            break  
        }
        else {
            Write-Host "Selection not confirmed. Please select again." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Invalid selection. Please select a valid number." -ForegroundColor Yellow
    }
}

# Install OpenSSH
$zipUrl = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64.zip"
$OpenSSLzipPath = "C:\Program Files\OpenSSH-Win64.zip"
$OpenSSLPath = "C:\Program Files"
Write-Host "Checking if OpenSSH is installed..."
$sshPath = Get-Command ssh -ErrorAction SilentlyContinue

if (-not $sshPath) {
    Write-Host "OpenSSH is not installed. Installing OpenSSH..." -ForegroundColor Yellow
    Write-Host "Downloading OpenSSH from GitHub..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $zipUrl -OutFile $OpenSSLzipPath
    Write-Host "Unzipping OpenSSH to Program Files..."
    Expand-Archive -Path $OpenSSLzipPath -DestinationPath $OpenSSLPath -Force
    Remove-Item $OpenSSLzipPath

    Write-Host "Installing ssh" -ForegroundColor Yellow
    & "C:\Program Files\OpenSSH-Win64\install-sshd.ps1"

    Write-Host "Adding OpenSSH to the system PATH..." -ForegroundColor Yellow
    [Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Program Files\OpenSSH-Win64", [EnvironmentVariableTarget]::Machine)

    Write-Host "Reloading the environment variables for the current session..."
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine) + ";" + [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)

    Write-Host "OpenSSH installation and setup complete." -ForegroundColor Green
}
else {
    Write-Host "OpenSSH is already installed at $sshPath, skipping installation....."  -ForegroundColor Green
}

#test connection
$test = @"
    echo '$SudoPassword' | sudo -S bash -c '
        set -e  # Exit immediately if a command exits with a non-zero status
        echo "-"
        echo "testing connection as sudo user......"
    '
"@

$test = $test -replace "`r`n", "`n"

Write-Host "testing connection for maximum 5s" 
ssh -i $PrivateKeyPath -o ConnectTimeout=5 $DestinationLinuxServer $test
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Connection Failed" -ForegroundColor Red
    Start-Sleep -Seconds 1
    exit
}
else {
    Write-Host "connection success! " -ForegroundColor Green
}

#comfirm file destination
$defaultPath = "/var/lib/smartermail/Domains"
do {
    $fileDestination = Read-Host -Prompt "Enter the file destination [Default: $defaultPath]"
    if ([string]::IsNullOrEmpty($fileDestination)) {
        $fileDestination = $defaultPath
    }

    $cmd = @"
    echo '$SudoPassword' | sudo -S bash -c '
        set -e  # Exit immediately if a command exits with a non-zero status
        echo "-"
        if [ ! -d "$fileDestination" ]; then
            exit 19
        else
            exit 0
        fi
    '
"@
    $cmd = $cmd -replace "`r`n", "`n"
    ssh -i $PrivateKeyPath $DestinationLinuxServer $cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "directory "$fileDestination" does not exist, Please try again" -ForegroundColor Red
    }
    else {
        $proceed = Read-Host -Prompt "Valid directory. Do you wish to proceed? [Y/n]" 
        if ($proceed -ne "Y" -and $proceed -ne "y" -and -not [string]::IsNullOrEmpty($proceed)) {
            Write-Host "Restarting the process..." -ForegroundColor Yellow
        }
        else {
            Write-Host "Proceeding with selected directory [$fileDestination]" -ForegroundColor Green
            break
        }
    }
} while ($true)

# Compress the SmarterMail folder into a zip
$SourceFolder = "C:\SmarterMail\Domains\$SelectedDomain"
$ZipFilePath = "$SourceFolder.zip"
Write-Host "Compressing the SmarterMail folder into a zip file..."
Compress-Archive -Path $SourceFolder -DestinationPath $ZipFilePath -Update

# Use the private key to SCP the zip file to the Linux machine
$RemotePath = "/home/$user/Domains.zip"
Write-Host "Copying the zip file to the Linux server to home directory $RemotePath ........"
scp -i $PrivateKeyPath $ZipFilePath ${DestinationLinuxServer}:${RemotePath}

# Unzip the zip folder into the selected directory
$commands = 
@"
    echo '$SudoPassword' | sudo -S bash -c '
        set -e  # Exit immediately if a command exits with a non-zero status
        echo "-"

        if ! command -v unzip &> /dev/null; then
            echo -e "Unzip not found, installing..."
            sudo apt-get update -qq && sudo apt-get install -y unzip -qq
        else
            echo -e "Unzip is already installed. Skipping installation...."
        fi

        if [ -d "$fileDestination"/"$SelectedDomain" ]; then
            exit 19
        fi
    
        unzip -n $RemotePath -d $fileDestination > /dev/null 2>&1 || true
        rm -f $RemotePath
        exit 0
    '
"@
$commands = $commands -replace "`r`n", "`n"

Write-Host "Initiating SSH connection...."  -ForegroundColor Green
ssh -i $PrivateKeyPath $DestinationLinuxServer $commands

# failover for existing directory
$command2= 
@"
    echo '$SudoPassword' | sudo -S bash -c '
        set -e  # Exit immediately if a command exits with a non-zero status
        echo "-"
        unzip -n $RemotePath -d $fileDestination > /dev/null 2>&1 || true
        rm -f $RemotePath
        exit 0
    '
"@
$command2= $command2 -replace "`r`n", "`n"

$command3=@"
    rm -f $RemotePath
    exit 20
"@
$command3= $command3 -replace "`r`n", "`n"

if($LASTEXITCODE -eq 19){
    Write-Host "WARNING: The directory "$fileDestination"/"$SelectedDomain" already exists!" -ForegroundColor Yellow
    $Choice=Read-Host -Prompt "Do You wish to continue to merge the directory? (existing file will not be overwritten) [Y/n]"
    if ($Choice -eq "Y" -or $Choice -eq "y" -or [string]::IsNullOrEmpty($Choice)) {
        Write-Host "Proceeding to merge the target directory"
        ssh -i $PrivateKeyPath $DestinationLinuxServer $command2
    }else{
        ssh -i $PrivateKeyPath $DestinationLinuxServer $command3
    }
}

# Prompt the result
Write-Host "Copying of folder " -NoNewline
Write-Host $SourceFolder -ForegroundColor Yellow -NoNewline
Write-Host " to " -NoNewline
Write-Host $fileDestination -ForegroundColor Cyan -NoNewline
if ($LASTEXITCODE -eq 0){
    Write-Host " COMPLETED!" 
    Write-Host "Migration success!" -ForegroundColor Green
}elseif($LASTEXITCODE -eq 20){
    Write-Host " FAILED !" 
    Write-Host "ERROR: The directory "$fileDestination"/"$SelectedDomain" already exists!" -ForegroundColor Red

}

#Cleanup
Write-Host "Cleaning up file........"
Remove-Item -Path $ZipFilePath
Start-Sleep -Seconds 2
 