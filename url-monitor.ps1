<#
.SYNOPSIS
    A GUI tool that monitors the availability of URLs from a list and displays their status.

.DESCRIPTION
    URL Monitor is a PowerShell GUI application that reads URLs from a text file and
    periodically checks their availability. It displays the status of each URL in a table,
    with color coding (green for successful connections, red for failures, yellow for in-progress checks).

    The tool performs HEAD requests with a 3-second timeout to efficiently check URL availability.
    Status checks run every 10 seconds when monitoring is active.

.PARAMETER None
    This script does not accept parameters.

.INPUTS
    urls.txt - A text file in the same directory as the script containing one URL per line.

.OUTPUTS
    No direct outputs except for the GUI display.

.NOTES
    File Name      : url-monitor.ps1
    Author         : Ayad Hammoudi
    Prerequisite   : PowerShell 5.1 or higher
                     .NET Framework 4.5 or higher
                     
    The script requires the following .NET assemblies:
    - System.Windows.Forms
    - System.Drawing
    - System.Net.Http

.EXAMPLE
    .\url-monitor.ps1
    
    Launches the URL Monitor GUI application which reads URLs from urls.txt in the same directory.

.FUNCTIONALITY
    - Reads URLs from a text file
    - Displays URLs and their connection status in a table view
    - Color codes status (green=success, red=failure, yellow=checking)
    - Monitors URL availability at regular intervals (10 seconds)
    - Allows starting and stopping the monitoring process
#>
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "URL Monitor"
$form.Size = New-Object System.Drawing.Size(960, 640)  # 20% smaller from 1200x800
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

# Create the DataGridView
$dataGridView = New-Object System.Windows.Forms.DataGridView
# Adjust the height to leave proper space for buttons at the bottom
$dataGridView.Size = New-Object System.Drawing.Size(880, 500)  # Reduced height to leave space for buttons
$dataGridView.Location = New-Object System.Drawing.Point(32, 32)  # 20% smaller from 40x40
$dataGridView.ColumnCount = 2
$dataGridView.Columns[0].Name = "URL"
$dataGridView.Columns[1].Name = "Status"
$dataGridView.AllowUserToAddRows = $false
$dataGridView.AllowUserToDeleteRows = $false
$dataGridView.ReadOnly = $true
$dataGridView.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$dataGridView.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill

# Adjust column fill weights to make Status column narrower
$dataGridView.Columns[0].FillWeight = 85  # URL column takes 85% of space
$dataGridView.Columns[1].FillWeight = 15  # Status column takes 15% of space

$dataGridView.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::AutoSize
$form.Controls.Add($dataGridView)

# Create buttons - position them closer to the DataGridView
$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = "RUN"
$runButton.Location = New-Object System.Drawing.Point(32, 550)  # Moved up to be closer to grid
$runButton.Size = New-Object System.Drawing.Size(96, 32)  # 20% smaller from 120x40
$form.Controls.Add($runButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "STOP"
$stopButton.Location = New-Object System.Drawing.Point(160, 550)  # Moved up to be closer to grid
$stopButton.Size = New-Object System.Drawing.Size(96, 32)  # 20% smaller from 120x40
$stopButton.Enabled = $false
$form.Controls.Add($stopButton)

# Global variables
$script:isRunning = $false
$script:timer = $null
$script:urls = $null

# Load URLs from file
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$urlsFilePath = Join-Path -Path $scriptPath -ChildPath "urls.txt"
$script:urls = Get-Content -Path $urlsFilePath -ErrorAction SilentlyContinue

if (-not $script:urls) {
    [System.Windows.Forms.MessageBox]::Show("URLs file not found or empty. Please add URLs to the file and try again.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

# Function to check a single URL
function Test-Url {
    param ($url)
    
    try {
        # Create request with timeout
        $request = [System.Net.WebRequest]::Create($url)
        $request.Timeout = 3000 # 3 seconds timeout
        $request.Method = "HEAD" # Only get headers, faster
        
        # Get response
        $response = $request.GetResponse()
        $statusCode = [int]$response.StatusCode
        $response.Close()
        
        return @{
            Status = "OK ($statusCode)"
            Success = $true
        }
    }
    catch [System.Net.WebException] {
        if ($_.Exception.Response -ne $null) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            return @{
                Status = "Error ($statusCode)"
                Success = $false
            }
        }
        else {
            if ($_.Exception.Status -eq [System.Net.WebExceptionStatus]::Timeout) {
                return @{
                    Status = "Timeout"
                    Success = $false
                }
            }
            else {
                return @{
                    Status = "Connection Error"
                    Success = $false
                }
            }
        }
    }
    catch {
        return @{
            Status = "Error: $($_.Exception.Message)"
            Success = $false
        }
    }
}

# Function to check all URLs
function Check-AllUrls {
    param(
        [switch]$CheckAllUrls = $false
    )
    
    # Skip if not running
    if (-not $script:isRunning) {
        return
    }

    # Process each URL
    for ($i = 0; $i -lt $script:urls.Count; $i++) {
        if (-not $script:isRunning) { 
            # Stop checking if stopped during execution
            break
        }
        
        $url = $script:urls[$i]
        $currentStatus = $dataGridView.Rows[$i].Cells[1].Value
        
        # Skip URLs that are already OK during refresh cycles
        if (-not $CheckAllUrls -and $currentStatus -like "OK*") {
            continue
        }
        
        # Update status to checking
        $dataGridView.Invoke([Action]{
            $dataGridView.Rows[$i].Cells[1].Value = "Checking..."
            $dataGridView.Rows[$i].DefaultCellStyle.BackColor = [System.Drawing.Color]::LightYellow
            # Force refresh
            $dataGridView.Refresh()
        })
        
        # Check URL
        $result = Test-Url -url $url
        
        # Update UI with result
        $dataGridView.Invoke([Action]{
            $dataGridView.Rows[$i].Cells[1].Value = $result.Status
            if ($result.Success) {
                $dataGridView.Rows[$i].DefaultCellStyle.BackColor = [System.Drawing.Color]::LightGreen
            }
            else {
                $dataGridView.Rows[$i].DefaultCellStyle.BackColor = [System.Drawing.Color]::LightCoral
            }
            # Force refresh
            $dataGridView.Refresh()
        })
    }
    
    # After all URLs are checked, restart the timer if we're still running
    if ($script:isRunning -and $script:timer -ne $null) {
        $script:timer.Stop()
        $script:timer.Start()
    }
}

# Start monitoring function
function Start-UrlMonitoring {
    # Initialize DataGridView
    $dataGridView.Rows.Clear()
    foreach ($url in $script:urls) {
        $dataGridView.Rows.Add($url, "Waiting...")
    }
    
    # Run initial check of all URLs
    Check-AllUrls -CheckAllUrls:$true
    
    # Setup timer for periodic checks
    $script:timer = New-Object System.Windows.Forms.Timer
    $script:timer.Interval = 10000 # 10 seconds
    $script:timer.Add_Tick({
        # Check ALL URLs on every refresh, even green/successful ones
        Check-AllUrls -CheckAllUrls:$true
        
        # Note: The timer will be restarted at the end of the Check-AllUrls function
        # This ensures the 10-second countdown starts after all URLs are checked
    })
    $script:timer.Start()
}

# Run button click event
$runButton.Add_Click({
    $script:isRunning = $true
    $runButton.Enabled = $false
    $stopButton.Enabled = $true
    Start-UrlMonitoring
})

# Stop button click event
$stopButton.Add_Click({
    $script:isRunning = $false
    $runButton.Enabled = $true
    $stopButton.Enabled = $false
    
    if ($script:timer) {
        $script:timer.Stop()
        $script:timer = $null
    }
})

# Form closing event
$form.Add_FormClosing({
    $script:isRunning = $false
    
    if ($script:timer) {
        $script:timer.Stop()
        $script:timer = $null
    }
})

# Add signature label
$signatureLabel = New-Object System.Windows.Forms.Label
$signatureLabel.Text = "Created By: Ayad Hammoudi"
$signatureLabel.AutoSize = $true
$signatureLabel.Location = New-Object System.Drawing.Point(760, 550)  # Positioned at bottom-right
$signatureLabel.Font = New-Object System.Drawing.Font("Arial", 8, [System.Drawing.FontStyle]::Italic)
$signatureLabel.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($signatureLabel)

# Show the form
[void]$form.ShowDialog()