#Requires -Version 5.0

$consoleAPI = @"
using System;
using System.Runtime.InteropServices;

public class ConsoleAPI
{
    ////////////////////////////////////////////////////////////////////////
    [StructLayout(LayoutKind.Sequential)]
    public struct COORD
    {
        public short X;
        public short Y;
    }

    [Flags]
    public enum ConsoleOutputModes : uint
    {
        ENABLE_PROCESSED_OUTPUT            = 0x0001,
        ENABLE_WRAP_AT_EOL_OUTPUT          = 0x0002,
        ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004,
        DISABLE_NEWLINE_AUTO_RETURN        = 0x0008,
        ENABLE_LVB_GRID_WORLDWIDE          = 0x0010,
    }

    public enum ControlKeyState {
        // /* dwControlKeyState bitmask */
        RIGHT_ALT_PRESSED = 1,
        LEFT_ALT_PRESSED = 2,
        RIGHT_CTRL_PRESSED = 4,
        LEFT_CTRL_PRESSED = 8,
        SHIFT_PRESSED = 16,
        NUMLOCK_ON = 32,
        SCROLLLOCK_ON = 64,
        CAPSLOCK_ON = 128,
        ENHANCED_KEY = 256,
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUT_RECORD
    {
        [FieldOffset(0)]
        public short EventType;
        //union {
        [FieldOffset(4)]
        public KEY_EVENT_RECORD KeyEvent;
        [FieldOffset(4)]
        public MOUSE_EVENT_RECORD MouseEvent;
        [FieldOffset(4)]
        public WINDOW_BUFFER_SIZE_RECORD WindowBufferSizeEvent;
        [FieldOffset(4)]
        public MENU_EVENT_RECORD MenuEvent;
        [FieldOffset(4)]
        public FOCUS_EVENT_RECORD FocusEvent;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct KEY_EVENT_RECORD
    {
        public uint bKeyDown;
        public short wRepeatCount;
        public short wVirtualKeyCode;
        public short wVirtualScanCode;
        public char UnicodeChar;
        public int dwControlKeyState;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSE_EVENT_RECORD
    {
        public COORD dwMousePosition;
        public int dwButtonState;
        public int dwControlKeyState;
        public int dwEventFlags;
    };
    
    [StructLayout(LayoutKind.Sequential)]
    public struct WINDOW_BUFFER_SIZE_RECORD
    {
        public COORD dwSize;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct MENU_EVENT_RECORD
    {
        public int dwCommandId;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct FOCUS_EVENT_RECORD
    {
        public uint bSetFocus;
    }

    public static int STD_OUTPUT_HANDLE = -11;
    public static int STD_INPUT_HANDLE  = -10;

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern int GetLastError();

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool PeekConsoleInput(IntPtr hConsoleInput, ref INPUT_RECORD lpBuffer, uint nLength, ref uint lpNumberOfEventsRead);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadConsoleInput(IntPtr hConsoleInput, ref INPUT_RECORD lpBuffer, uint nLength, ref uint lpNumberOfEventsRead);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    ////////////////////////////////////////////////////////////////////////
}
"@

Add-Type $consoleAPI

[char]$ESC = 0x1b

[uint32]$UIElementIDAutoAssign = 1
$UIElementIDsInUse = [System.Collections.Generic.List[uint32]]::new()
# Button ID 0 is returned when the user exits a form with ESCAPE
# instead of pressing one of the provided buttons
$UIElementIDsInUse.Add(0)

$hIn  = [ConsoleAPI]::GetStdHandle( [ConsoleAPI]::STD_INPUT_HANDLE )

class UIForm {
    [uint32]$ID
    [string]$Name
    [bool]$Border
    [System.Collections.Generic.List[UIElement]]$Elements = [System.Collections.Generic.List[UIElement]]::new()

    Add ([UIElement[]]$Element) {
        foreach ($e in $Element) {
            $this.Elements.Add($e)
        }
    }

    Remove ([UIElement]$Element) {
        $this.Elements.Remove($Element)
    }

    [UIElement] Show () {
        [console]::Clear()
        [console]::SetCursorPosition(0, 0)
        if ($this.Border) {
            # Top edge
            Write-Host "$script:ESC(0l$('q' * ($global:Host.UI.RawUI.WindowSize.Width - 2))k$script:ESC(B"
            # Sides
            for ($i = 1; $i -lt $global:Host.UI.RawUI.WindowSize.Height - 1; $i++) {
                [console]::SetCursorPosition(0, $i)
                Write-Host "$script:ESC(0x$script:ESC(B"
                [console]::SetCursorPosition($global:Host.UI.RawUI.WindowSize.Width - 1, $i)
                Write-Host "$script:ESC(0x$script:ESC(B"
            }
            # Bottom edge
            Write-Host "$script:ESC(0m$('q' * ($global:Host.UI.RawUI.WindowSize.Width - 2))j$script:ESC(B"
        }
        foreach ($UIElement in $this.Elements) {
            switch ($UIElement.GetType().Name) {
                'UIButton' {
                    Show-UIButton -Button $UIElement
                }
                'UICheckbox' {
                    Show-UICheckBox -Checkbox $UIElement
                }
                'UILabel' {
                    Show-UILabel -Label $UIElement
                }
            }
        }
        [console]::SetCursorPosition(0, 0)
        return Wait-UIClick -UIElements $this.Elements
    }
}

class UIElement {
    [uint32]$ID
    [string]$Text
    [int]$TextPadding
    [int[]]$X
    [int[]]$Y
}

class UIButton : UIElement {
    [string]$HLStyle
}

class UICheckbox : UIElement {
    [string]$HLStyle
    [bool]$Checked
}

class UILabel : UIElement {}

function New-UICheckBox {
    Param (
        [ValidateScript({ $_ -notin $UIElementIDsInUse })]
        [uint32]$ID = $script:UIElementIDAutoAssign++,
        [Parameter( Mandatory = $true )]
        [string]$Text,
        [switch]$Checked,
        [ValidateSet('Underline', 'ColorText', 'ColorElement', 'None')]
        [string]$HighlightStyle = 'None',
        [int]$X = $host.UI.RawUI.WindowSize.Width  / 2, # Pseudo-Center by default
        [int]$Y = $host.UI.RawUI.WindowSize.Height / 2, # Center by default
        [int]$TextPadding = 1
    )

    $UIElementIDsInUse.Add($ID)
    [int]$ElementLength = $X + $Text.Length + $TextPadding + 3

    return [UICheckbox]@{
        'ID'          = $ID
        'Text'        = $Text
        'TextPadding' = $TextPadding
        'X'           = $X..$ElementLength
        'Y'           = $Y
        'HLStyle'     = $HighlightStyle
        'Checked'     = $Checked
    }
}

function New-UIButton {
    Param (
        [ValidateScript({ $_ -notin $UIElementIDsInUse })]
        [uint32]$ID = $script:UIElementIDAutoAssign++,
        [Parameter( Mandatory = $true )]
        [string]$Text,
        [int]$X = $host.UI.RawUI.WindowSize.Width  / 2, # Pseudo-Center by default
        [int]$Y = $host.UI.RawUI.WindowSize.Height / 2, # Center by default
        [ValidateSet('Underline', 'ColorText', 'ColorElement', 'None')]
        [string]$HighlightStyle = 'ColorElement',
        [int]$TextPadding = 4
    )

    $UIElementIDsInUse.Add($ID)
    [int]$ButtonLength = $X + $Text.Length + $TextPadding * 2 + 1

    return [UIButton]@{
        'ID'          = $ID
        'Text'        = $Text
        'TextPadding' = $TextPadding
        'X'           = $x..$ButtonLength
        'Y'           = $y..($y + 2 )
        'HLStyle'     = $HighlightStyle
    }
}

function New-UILabel {
    Param (
        [ValidateScript({ $_ -notin $UIElementIDsInUse })]
        [uint32]$ID = $script:UIElementIDAutoAssign++,
        [Parameter( Mandatory = $true )]
        [string]$Text,
        [int]$X = $host.UI.RawUI.WindowSize.Width  / 2, # Pseudo-Center by default
        [int]$Y = $host.UI.RawUI.WindowSize.Height / 2, # Center by default
        [int]$TextPadding = 0
    )

    $UIElementIDsInUse.Add($ID)

    return [UILabel]@{
        'ID'          = $ID
        'Text'        = $Text -replace "`n"
        'TextPadding' = $TextPadding
        'X'           = $X..($X + $Text.Length - 1)
        'Y'           = $Y
    }
}

function Show-UIButton {
    Param (
        [Parameter( ValueFromPipeline = $true )]
        [UIButton[]]$Button
    )

    begin {
        # Workaround for PS pipeline bug (I'm pretty sure?)
        [array]$InButtons = @()
    }

    process {
        $ButtonContent = "$(' ' * $Button.TextPadding)$($Button.Text)$(' ' * $Button.TextPadding)"

        [console]::SetCursorPosition($Button.X[0], $Button.Y[0])
        Write-Host "$ESC(0l$("q" * $ButtonContent.Length)k$ESC(B"
        [console]::SetCursorPosition($Button.X[0], $Button.Y[1])
        Write-Host "$ESC(0x$ESC(B$ButtonContent$ESC(0x$ESC(B"
        [console]::SetCursorPosition($Button.X[0], $Button.Y[-1])
        Write-Host "$ESC(0m$("q" * $ButtonContent.Length)j$ESC(B"

        $InButtons += $Button
    }

    end {
        return $InButtons
    }
}

function Show-UICheckBox {
    Param (
        [Parameter( ValueFromPipeline = $true )]
        [UICheckbox[]]$Checkbox
    )

    begin {
        [array]$InCheckBoxes = @()
    }

    process {
        [console]::SetCursorPosition($Checkbox.X[0], $Checkbox.Y[0])
        if ($Checkbox.Checked) {
            Write-Host "[X]$(' ' * $Checkbox.TextPadding)$($Checkbox.Text)"
        } else {
            Write-Host "[ ]$(' ' * $Checkbox.TextPadding)$($Checkbox.Text)"
        }
        $InCheckBoxes += $Checkbox
    }

    end {
        return $InCheckBoxes
    }
}

function Show-UILabel {
    Param (
        [Parameter( ValueFromPipeline = $true )]
        [UILabel[]]$Label
    )

    begin {
        [array]$InLabels = @()
    }

    process {
        [console]::SetCursorPosition($Label.X[0], $Label.Y[0])
        Write-Host $Label.Text
        $InLabels += $Label
    }

    end {
        return $InLabels
    }
}

function Reset-UIElementIDs {
    [uint32]$script:UIElementIDAutoAssign = 0
    $script:UIElementIDsInUse = [System.Collections.Generic.List[uint32]]::new()
}

function Wait-UIClick {
    Param (
        [Parameter( ValueFromPipeline = $true )]
        [UIElement[]]$UIElements
    )

    begin {
        # Disable mouse text selection so we can grab mouse as input
        # ENABLE_MOUSE_INPUT    0x0010
        # ENABLE_EXTENDED_FLAGS 0x0080
        # ENABLE_WINDOW_INPUT   0x0008
        [uint32]$oldConMode  =  0
        $ClickedOnButton     = -1
        [bool]$ClickOccurred = $false
        $null = [ConsoleAPI]::GetConsoleMode($hIn, [ref]$oldConMode)
        $null = [ConsoleAPI]::SetConsoleMode($hIn, 0x0010 -bor 0x0080 -bor 0x0008)
        [console]::CursorVisible = $false
    }

    process {
        while (-not $ClickOccurred) {
            $lpBuffer = New-Object ConsoleAPI+INPUT_RECORD
            do {
                $null = [ConsoleAPI]::ReadConsoleInput($hIn, [ref]$lpBuffer, 1, [ref]1)
            } until (($lpBuffer.EventType -eq 2) -or
                    ($lpBuffer.EventType -eq 1 -and $lpBuffer.KeyEvent.wVirtualKeyCode -eq 0x1B))
    
            if ($lpBuffer.MouseEvent.dwEventFlags -eq 1) {
                # Mouse move event
                foreach ($UIElement in $UIElements) {
                    if (($lpBuffer.MouseEvent.dwMousePosition.X -in $UIElement.X) -and ($lpBuffer.MouseEvent.dwMousePosition.Y -in $UIElement.Y)) {
                        # Mouse is over top of UIElement - highlight it
                        switch ($UIElement.GetType().Name) {
                            'UIButton' {
                                [console]::SetCursorPosition($UIElement.X[0], $UIElement.Y[1])
                                switch ($UIElement.HLStyle) {
                                    'Underline' {
                                        Write-Host "|$(' ' * $UIElement.TextPadding)$ESC[4m$($UIElement.Text)$ESC[0m$(' ' * $UIElement.TextPadding)|"
                                    }
                                    'ColorElement' {
                                        [console]::SetCursorPosition($UIElement.X[0], $UIElement.Y[0])
                                        Write-Host "$('▄' * $UIElement.X.Count)"
                                        [console]::SetCursorPosition($UIElement.X[0], $UIElement.Y[1])
                                        Write-Host " $(' ' * $UIElement.TextPadding)$($UIElement.Text)$(' ' * $UIElement.TextPadding) " -ForegroundColor $Host.UI.RawUI.BackgroundColor -BackgroundColor $Host.UI.RawUI.ForegroundColor
                                        [console]::SetCursorPosition($UIElement.X[0], $UIElement.Y[2])
                                        Write-Host "$('▀' * $UIElement.X.Count)"
                                    }
                                    'ColorText' {
                                        $ButtonContent = "$(' ' * $UIElement.TextPadding)$($UIElement.Text)$(' ' * $UIElement.TextPadding)"
                                        [console]::SetCursorPosition($UIElement.X[1], $UIElement.Y[1])
                                        Write-Host $ButtonContent -ForegroundColor $Host.UI.RawUI.BackgroundColor -BackgroundColor $Host.UI.RawUI.ForegroundColor 
                                    }
                                    default {}
                                }
                            }
                            'UICheckbox' {
                                [console]::SetCursorPosition($UIElement.X[0], $UIElement.Y[0])
                                # Always underline for now
                                switch ($UIElement.HLStyle) {
                                    'Underline' {
                                        if ($UIElement.Checked) {
                                            Write-Host "$ESC[4m[X]$(' ' * $Checkbox.TextPadding)$($Checkbox.Text)$ESC[0m"
                                        } else {
                                            Write-Host "$ESC[4m[ ]$(' ' * $Checkbox.TextPadding)$($Checkbox.Text)$ESC[0m"
                                        }
                                    }
                                    'ColorElement' {
                                        if ($UIElement.Checked) {
                                            Write-Host "[X]$(' ' * $Checkbox.TextPadding)$($Checkbox.Text)" -ForegroundColor $Host.UI.RawUI.BackgroundColor -BackgroundColor $Host.UI.RawUI.ForegroundColor
                                        } else {
                                            Write-Host "[ ]$(' ' * $Checkbox.TextPadding)$($Checkbox.Text)" -ForegroundColor $Host.UI.RawUI.BackgroundColor -BackgroundColor $Host.UI.RawUI.ForegroundColor
                                        }
                                    }
                                    'ColorText' {
                                        [console]::SetCursorPosition($UIElement.X[2], $UIElement.Y[0])
                                        Write-Host "$(' ' * $Checkbox.TextPadding)$($Checkbox.Text)" -ForegroundColor $Host.UI.RawUI.BackgroundColor -BackgroundColor $Host.UI.RawUI.ForegroundColor
                                    }
                                    default {}
                                }
                            }
                        }
                    } else {
                        # Restore normal look, as mouse pointer is now off the element
                        switch ($UIElement.GetType().Name) {
                            'UIButton' {
                                $null = Show-UIButton -Button $UIElement
                            }
                            'UICheckBox' {
                                $null = Show-UICheckBox -Checkbox $UIElement
                            }
                        }
                    }
                }
            } elseif ($lpBuffer.MouseEvent.dwButtonState -eq 0x01) {
                # single left click event
                foreach ($UIElement in $UIElements) {
                    if (($lpBuffer.MouseEvent.dwMousePosition.X -in $UIElement.X) -and ($lpBuffer.MouseEvent.dwMousePosition.Y -in $UIElement.Y)) {
                        # Mouse was over top of UIElement when click occured
                        switch ($UIElement.GetType().Name) {
                            'UIButton' {
                                $ClickedOnButton = $UIElement
                                # This will break the loop
                                $ClickOccurred = $true
                            }
                            'UICheckbox' {
                                $UIElement.Checked = -not $UIElement.Checked
                                $null = Show-UICheckBox -Checkbox $UIElement
                            }
                        }
                    }
                }
            } elseif ($lpBuffer.KeyEvent.wVirtualKeyCode -eq 0x1B) {
                # User pressed ESCAPE, we'll return the buttonID 0
                $ClickedOnButton = [UIElement]@{'ID' = 0; 'Text' = 'User quit with ESCAPE key'}
                $ClickOccurred = $true
            }
        }
    }

    end {
        # Restore default console behaviour
        $null = [ConsoleAPI]::SetConsoleMode($hIn, $oldConMode)
        [console]::CursorVisible = $true

        return $ClickedOnButton
    }
}
