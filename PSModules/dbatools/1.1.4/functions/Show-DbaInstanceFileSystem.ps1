function Show-DbaInstanceFileSystem {
    <#
    .SYNOPSIS
        Shows file system on remote SQL Server in a local GUI and returns the selected directory name

    .DESCRIPTION
        Similar to the remote file system popup you see when browsing a remote SQL Server in SQL Server Management Studio, this function allows you to traverse the remote SQL Server's file structure.

        Show-DbaInstanceFileSystem uses SQL Management Objects to browse the directories and what you see is limited to the permissions of the account running the command.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, FileSystem
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Show-DbaInstanceFileSystem

    .EXAMPLE
        PS C:\> Show-DbaInstanceFileSystem -SqlInstance sql2017

        Shows a list of databases using Windows Authentication to connect to the SQL Server. Returns a string of the selected path.

    .EXAMPLE
        PS C:\> Show-DbaInstanceFileSystem -SqlInstance sql2017 -SqlCredential $cred

        Shows a list of databases using SQL credentials to connect to the SQL Server. Returns a string of the selected path.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    begin {
        try {
            Add-Type -AssemblyName PresentationFramework
        } catch {
            Stop-Function -Message "Windows Presentation Framework required but not installed."
            return
        }

        function Add-TreeItem {
            param (
                [string]$name,
                [object]$parent,
                [string]$tag
            )

            $childitem = New-Object System.Windows.Controls.TreeViewItem

            $textblock = New-Object System.Windows.Controls.TextBlock
            $textblock.Margin = "5,0"

            $stackpanel = New-Object System.Windows.Controls.StackPanel
            $stackpanel.Orientation = "Horizontal"

            $image = New-Object System.Windows.Controls.Image
            $image.Height = 20
            $image.Width = 20
            $image.Stretch = "Fill"

            if ($name.length -eq 1) {
                $image.Source = $diskicon
                $textblock.Text = "$name`:"
                $childitem.Tag = "$name`:"

            } else {
                $image.Source = $foldericon
                $textblock.Text = $name
                $childitem.Tag = "$tag\$name"
            }

            [void]$stackpanel.Children.Add($image)
            [void]$stackpanel.Children.Add($textblock)

            $childitem.Header = $stackpanel

            [void]$childitem.Items.Add("*")
            [void]$parent.Items.Add($childitem)
        }

        function Get-SubDirectory {
            param (
                [string]$nameSpace,
                [object]$treeviewItem
            )

            $textbox.Text = $nameSpace
            try {
                $dirs = $server.EnumDirectories($nameSpace)
            } catch {
                return
            }
            $subdirs = $dirs.Name

            foreach ($subdir in $subdirs) {
                if (!$subdir.StartsWith("$") -and $subdir -ne 'System Volume Information') {
                    Add-TreeItem -Name $subdir -Parent $treeviewItem -Tag $nameSpace
                }
            }
        }

        function Convert-b64toimg {
            param ($base64)

            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String($base64)
            $bitmap.EndInit()
            $bitmap.Freeze()
            return $bitmap
        }

        $diskicon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABkAAAAZCAYAAADE6YVjAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAACxEAAAsRAX9kX5EAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAJtSURBVEhLtZJLa1NBGIa78ze4EZeu3bjS36BduVOsVCGmUqo1QlMaTV3E0oVugm0obdUQTZtYEnNvboTczjlN0ubaWE2aWGhuVQQXKbzOBM+BmokinA48nI+XmefjfDNDAE4dZig3zFBumKHcMEO5YYZywwwppVL5QrG4+217OweO30IiySPJCT1ozQsp7GTzoHvoXpZDpC/4Ut2/nc7sRIhYqO3Xuq1GA512C53WSY46bbSaTVQr1S5pLNAz9OyfPopUlMuf9KFAWO9yeit2uwtWiw1Ohwd+XwBBfxjBAIF+f9dkLzZ9QTg/umGzuuGwe+F0uivBQEhPXcwmJtM6HOSA2+VDOBRBaisNno4nwSOR4PqIx5LgyRhzuQK4NIdYPE7ORXsO6hK9FKkYHb0Po3ENGXIHzVabRP9ex13gsHkI7qcdobwTyUgapncWUBdZ/U3Gxx/j9aoJqVQGpd0KCsWvhPpAavXv8Ls5KCfGcMN7EcOay9CpX8D8/gOoS/RSTjQxLK6QlyRgt1xFvlAn1AZSq/yAZzOCW7pruHpwBlc056C+8xxr5o3BTRSKid6fZHM5VKoH2PvcIjQH0mwcwx/gcFN1HcOxs7ikPI+ZsTnyWHygLtFLkQq1ehZTUxpYrRvI58sQhAIhP5Bsbg9+Txzzcy+hddzDkwUVnk3PY1arA3WJXopUmEwWjIzcheqRGsa3ZjK65b+y8GoJy0tvyEWvY9W+CJvXhqczup6DukQvRSqi0QQMhhVMTk5DqXzYm+v/oFA8IJPQkhdqBnWJXopUnCbMUG6YodwwQ7lhhnLDDOWGGcoNM5QXDP0CA9dqCMSSjzkAAAAASUVORK5CYII="
        $foldericon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABkAAAAZCAYAAADE6YVjAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAACxEAAAsRAX9kX5EAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAU0SURBVEhLtZXpU5NXFIf9q/qto9bRuhc3xqUiUK3KoLYq6ihu1VIU1DpjRZ3BHVR8i6hUkDUJASNL2EJIWLKvBLJAAmHRpwfb6ai10Q/2w29u3pP3/p57zrn3vnOA/13/CkwMlzLuv0rMfYaoM59R+1ki1lwiFtHgGcIDuYT6fiZoPsWI6SSBnmyGeo4yZDxN2KEQHXr54H3Pdx5mNe6/QnzkGtMxNVNjeqK+AkLWQ/iMWdg7sxnz3uZ1vIrJSBnx0O9MhBQmggqxkRJC9hsEzFc+Dol5cpkcFaNXHbyasTMVNzARqWXEeZv+lh+xG/OIRWrgtU5ebxG1yu9meb+JEct57C+2fwLEe04g95mOPxJV8JphCcPUuBOHfg/6qm/pa8klNvyA6fFqZqbqZaxiZqKWQF8uVm3qp0LuMTNZyfREuUx+JuEo8agLe1smHTXpGLXSB3O+lKqMV5N1UtZypqJ/SCwHS2P6J0Iis5BqgTyR3tyVcIj4mAtL807aq1IxqLJwdR6TJhfL/xUCK3kjn/Ekg9rvPg6JevL/hlQJ5KmU4qGEg9IXCwNN22ir3ES3ap9AjjLqvU48/FBgN0SFeAzZDDSk3nnf852HWY25zxKPFEut/4JMRmcX5mM8bKJPm0bLs/V01e/B2X6IsPMyscAtRt2XRZdwdx1kQPsJ5Rp1nRGIZCKQqZhs09FiCTuJhQyYNFtoLl9HZ20mjtb9BK0XJJsrhG3nZJvn4Wr/AUfbEc+I/fFsI//xfAcwq4gjR0pTxPRkhQAeMh66zavpHkYDWoz1m3j5ZDWd1duxN+9muO80IVuejCcImI7h0W/F2boLtyFfrBJAwtZTjAdvMTn+VFZ/j7HADSbGahh2FGGoWYeuLImOynRsL3bg7zksgGP4DPvwdu2W52wp4wH6NJvFKgEkaP2J6LA0dKxMxruM+q9LFnfxmH+hu3oVTY+S0FekyFbdhrdzr1wnWXg6MnC1phBwVuOxqelvSBOrBJCRgWOM+a9JmUqI+AoJea4SlMY6pamdlStoVJbTVr6BQemPq22ngDJwNm/B3rSKgFuPzz0gmXwEEug7TMTzm5TpDkHXZYbtFxm2XsTenkX7s2VoS76m9cla+lUbcbxMlQxmAclYNEsIuzSE3N0CSRWrBBC/6RBB50XC3kICtl/xD+bh78/DIveWvnwJDQ8W0iJ96atNxtYoIN0GrA1JWOoX4Ler8Dq7MKu3iFUCiK/ngKw8Xy7EAnwDZ6UXOXjkGh/QZdL2dDHq+1/RXLoSc80aMV+LTbsKm3opHvU8buoqKdC1YFKliFUCiKdrr6w8B7/lAu7eUzi7j+PoPCIH8XtaHi9CXTyPZmUJpqqVDKq/wapZgUO9mKB2LqmlVSQ9bKG3fqNYJYA4O3bhMZ2QDHJxdGVj0x/E2rafXnW6QBaiKZ7LS2URpucrGFQtF8hyHJqlDGkXcLz0OnuVUno/loldvwO37He3MQebXB3W1n1yMe7BKBNnIeqiL9GVLHwDsaiWYdMsw6pehl1A7bXraK7birlhh1glgLi6T2Br24tZmyqr34BJvZn+xu1y2r+l9fF86m5+gbZ4PsbnazDXJ9OvXv9mNNUl45LSDck3x91bKFYJIF7TJWVQl6mYNGn6fl0WpoYMeupSaK9Yje7RcjmMqbSWZ9gNz9crxvotSq86TTHWpiiGmk2KUZWuOAyXlBG3Snnb8x3A2wp6m3b6rE+wtp+nq2oDL0oX01CaQndjAVZjbdGH5vyXPhj83Ppg8POKOX8Cx4yjZbQFLr4AAAAASUVORK5CYII="
        $dbatoolsicon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABkAAAAZCAYAAADE6YVjAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAO9SURBVEhL3VVdTFNXHO9MzPTF+OzDeBixFdTMINIWsAUK3AIVkFvAIQVFRLYZKR8Wi1IEKV9DYB8PGFAyEx8QScySabYY5+I2JvK18iWISKGk0JGhLzA3+e2c29uHtpcvH/0lv9yennN+v3vO/3fOFb2fCAg4vXWPNOmMRJ745TtTSskqeElviGXJ0XtkWvjJkyGLPoFAVQZoe/NkX/n6Mh/ysu4Qy7WZdJAutxRW6zT6LcNQaE4LiGgREH4cibpCMNqzCIk9hbScEoSSZ0zKOa7fRxG/k5d1h8ukvO4a5ubmMT1jw5E0vZcBZWzqOTS3dcB8tRXZeRX4/v5DZH5uIu0Wrn8NEzaNDjgYoUPd120oMjViX2iql8H6ZFd8DzE7eFl3iOWpuyQydlh44kbJroilSd8RuQ+cqh7wC9Z+JJaxY8KTN0gp+5Yk9DaREzYhb5FOBwZFZ6LlZifKa5ux//AxYTHCvSEp8A9O5n77B6dwqXS119guZ+GrGq9jfn4eM7ZZxB/PdxN2UfOpHq3kRWq/uoE8Yx3u/fQLzhSYUdN0g+tfN126z0oxNj6BJz0Dq0b4E2UawuJzuPhKyZmKYr/AocgMrk37VzWRBLGRdE/psuXqk9wkT/GNUCJLWqS3By/rDh9FxjaSrnahiZ7cq8wCUzKImLIJqC+Ngbk4gmjjIKKKB6Aq7l+OLBmfVF0YnlQZR1p4eSd2y5IiyEr+oyJ0CwIi0gUNKAOPmnG04Q0utf+DHweWkFjjQOyVWajLpsCUPkeUcRgqAzE09Dfz8k64aqI9YcDziUk87bMgOCZL0CQ0ux2J9UtIbXyFwall/PD0NeLKrU6DkhGymj8RXtRDjU7x8k64TKpJQmi6bLOzSEgv8DYhNWMujiK+9jU0VQs4Vm/H2MwSOh4vcP+rii2cQVh+F+IqbRJe3glyReuoSFBUJtpu3eWulv2h3ueE1iOu0g5N9QL3jLk8jerbdrz59y1yGoYQUdSLsII/CLscIsD9UPrLUz4myXhBhWjCPMVdPBBnhMbsIAZzSDDbcOvRIhyLy6i4+Qyq82QFxECR9xjK/K5OXtodNHo+CsW2tagunbxADbK+sXP16Bv/G7lNQ8hpHEX21UGoDb/j8NmfoSzoNvCymwdTPvMotsKGB32LaL1H0mS0oOHOFLpH/0L3iAOF3/YSk4dgTBMh/JTNgdVbtzNl1il12UuSpHE+SRayTb0IL3yCMP2vUJKtUuh/szNNK8Jfxw3BZNpiMoGjiKPJm54Ffw8gEv0PQRYX7wDAUKEAAAAASUVORK5CYII="
    }

    process {
        if (Test-FunctionInterrupt) { return }

        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }

        # Create XAML form in Visual Studio, ensuring the ListView looks chromeless
        [xml]$xaml = '<Window
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Locate Folder" Height="620" Width="440" Background="#F0F0F0"
        WindowStartupLocation="CenterScreen">
    <Grid>
        <TreeView Name="treeview" Height="462" Width="391" Background="#FFFFFF" BorderBrush="#FFFFFF" Foreground="#FFFFFF" Margin="11,36,11,79"/>
        <Label x:Name="label" Content="Select the folder:" HorizontalAlignment="Left" Margin="15,4,0,0" VerticalAlignment="Top"/>
        <Label x:Name="path" Content="Selected Path" HorizontalAlignment="Left" Margin="15,502,0,0" VerticalAlignment="Top"/>
        <TextBox Name="textbox" HorizontalAlignment="Left" Height="Auto" Margin="111,504,0,0" TextWrapping="NoWrap" Text="C:\" VerticalAlignment="Top" Width="292"/>
        <Button Name="okbutton" Content="OK" HorizontalAlignment="Left" Margin="241,540,0,0" VerticalAlignment="Top" Width="75"/>
        <Button Name="cancelbutton" Content="Cancel" HorizontalAlignment="Left" Margin="328.766,540,0,0" VerticalAlignment="Top" Width="75"/>
    </Grid>
</Window>
'
        # Turn XAML into PowerShell objects
        $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
        $window.icon = $dbatoolsicon

        $xaml.SelectNodes("//*[@Name]") | ForEach-Object { Set-Variable -Name ($_.Name) -Value $window.FindName($_.Name) -Scope Script }

        try {
            $drives = ($server.EnumAvailableMedia()).Name
        } catch {
            Stop-Function -Message "No access to remote SQL Server files." -Target $SqlInstance
            return
        }

        foreach ($drive in $drives) {
            $drive = $drive.Replace(":", "")
            Add-TreeItem -Name $drive -Parent $treeview -Tag $drive
        }

        $window.Add_SourceInitialized( {
                [System.Windows.RoutedEventHandler]$Event = {
                    if ($_.OriginalSource -is [System.Windows.Controls.TreeViewItem]) {
                        $treeviewItem = $_.OriginalSource
                        $treeviewItem.items.clear()
                        Get-SubDirectory -NameSpace $treeviewItem.Tag -TreeViewItem $treeviewItem
                    }
                }
                $treeview.AddHandler([System.Windows.Controls.TreeViewItem]::ExpandedEvent, $Event)
                $treeview.AddHandler([System.Windows.Controls.TreeViewItem]::SelectedEvent, $Event)
            })

        $okbutton.Add_Click( {
                $window.Close()
            })

        $cancelbutton.Add_Click( {
                $textbox.Text = $null
                $window.Close()
            })

        $null = $window.ShowDialog()
    }

    end {

        if ($textbox.Text.Length -gt 0) {
            $drive = $textbox.Text + '\'
            return $drive
        }
    }
}
# SIG # Begin signature block
# MIIZewYJKoZIhvcNAQcCoIIZbDCCGWgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUVdVAYYGfoHTZhbH4Rc1BwWxo
# RkegghSJMIIE/jCCA+agAwIBAgIQDUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgVGltZXN0YW1waW5nIENBMB4XDTIxMDEwMTAwMDAwMFoXDTMxMDEw
# NjAwMDAwMFowSDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMu
# MSAwHgYDVQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyMTCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBAMLmYYRnxYr1DQikRcpja1HXOhFCvQp1dU2UtAxQ
# tSYQ/h3Ib5FrDJbnGlxI70Tlv5thzRWRYlq4/2cLnGP9NmqB+in43Stwhd4CGPN4
# bbx9+cdtCT2+anaH6Yq9+IRdHnbJ5MZ2djpT0dHTWjaPxqPhLxs6t2HWc+xObTOK
# fF1FLUuxUOZBOjdWhtyTI433UCXoZObd048vV7WHIOsOjizVI9r0TXhG4wODMSlK
# XAwxikqMiMX3MFr5FK8VX2xDSQn9JiNT9o1j6BqrW7EdMMKbaYK02/xWVLwfoYer
# vnpbCiAvSwnJlaeNsvrWY4tOpXIc7p96AXP4Gdb+DUmEvQECAwEAAaOCAbgwggG0
# MA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsG
# AQUFBwMIMEEGA1UdIAQ6MDgwNgYJYIZIAYb9bAcBMCkwJwYIKwYBBQUHAgEWG2h0
# dHA6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAfBgNVHSMEGDAWgBT0tuEgHf4prtLk
# YaWyoiWyyBc1bjAdBgNVHQ4EFgQUNkSGjqS6sGa+vCgtHUQ23eNqerwwcQYDVR0f
# BGowaDAyoDCgLoYsaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJl
# ZC10cy5jcmwwMqAwoC6GLGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFz
# c3VyZWQtdHMuY3JsMIGFBggrBgEFBQcBAQR5MHcwJAYIKwYBBQUHMAGGGGh0dHA6
# Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBPBggrBgEFBQcwAoZDaHR0cDovL2NhY2VydHMu
# ZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJRFRpbWVzdGFtcGluZ0NB
# LmNydDANBgkqhkiG9w0BAQsFAAOCAQEASBzctemaI7znGucgDo5nRv1CclF0CiNH
# o6uS0iXEcFm+FKDlJ4GlTRQVGQd58NEEw4bZO73+RAJmTe1ppA/2uHDPYuj1UUp4
# eTZ6J7fz51Kfk6ftQ55757TdQSKJ+4eiRgNO/PT+t2R3Y18jUmmDgvoaU+2QzI2h
# F3MN9PNlOXBL85zWenvaDLw9MtAby/Vh/HUIAHa8gQ74wOFcz8QRcucbZEnYIpp1
# FUL1LTI4gdr0YKK6tFL7XOBhJCVPst/JKahzQ1HavWPWH1ub9y4bTxMd90oNcX6X
# t/Q/hOvB46NJofrOp79Wz7pZdmGJX36ntI5nePk2mOHLKNpbh6aKLzCCBRowggQC
# oAMCAQICEAMFu4YhsKFjX7/erhIE520wDQYJKoZIhvcNAQELBQAwcjELMAkGA1UE
# BhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2lj
# ZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUg
# U2lnbmluZyBDQTAeFw0yMDA1MTIwMDAwMDBaFw0yMzA2MDgxMjAwMDBaMFcxCzAJ
# BgNVBAYTAlVTMREwDwYDVQQIEwhWaXJnaW5pYTEPMA0GA1UEBxMGVmllbm5hMREw
# DwYDVQQKEwhkYmF0b29sczERMA8GA1UEAxMIZGJhdG9vbHMwggEiMA0GCSqGSIb3
# DQEBAQUAA4IBDwAwggEKAoIBAQC8v2N7q+O/vggBtpjmteofFo140k73JXQ5sOD6
# QLzjgija+scoYPxTmFSImnqtjfZFWmucAWsDiMVVro/6yGjsXmJJUA7oD5BlMdAK
# fuiq4558YBOjjc0Bp3NbY5ZGujdCmsw9lqHRAVil6P1ZpAv3D/TyVVq6AjDsJY+x
# rRL9iMc8YpD5tiAj+SsRSuT5qwPuW83ByRHqkaJ5YDJ/R82ZKh69AFNXoJ3xCJR+
# P7+pa8tbdSgRf25w4ZfYPy9InEvsnIRVZMeDjjuGvqr0/Mar73UI79z0NYW80yN/
# 7VzlrvV8RnniHWY2ib9ehZligp5aEqdV2/XFVPV4SKaJs8R9AgMBAAGjggHFMIIB
# wTAfBgNVHSMEGDAWgBRaxLl7KgqjpepxA8Bg+S32ZXUOWDAdBgNVHQ4EFgQU8MCg
# +7YDgENO+wnX3d96scvjniIwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsG
# AQUFBwMDMHcGA1UdHwRwMG4wNaAzoDGGL2h0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNv
# bS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMDWgM6Axhi9odHRwOi8vY3JsNC5kaWdp
# Y2VydC5jb20vc2hhMi1hc3N1cmVkLWNzLWcxLmNybDBMBgNVHSAERTBDMDcGCWCG
# SAGG/WwDATAqMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20v
# Q1BTMAgGBmeBDAEEATCBhAYIKwYBBQUHAQEEeDB2MCQGCCsGAQUFBzABhhhodHRw
# Oi8vb2NzcC5kaWdpY2VydC5jb20wTgYIKwYBBQUHMAKGQmh0dHA6Ly9jYWNlcnRz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFNIQTJBc3N1cmVkSURDb2RlU2lnbmluZ0NB
# LmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4IBAQCPzflwlQwf1jak
# EqymPOc0nBxiY7F4FwcmL7IrTLhub6Pjg4ZYfiC79Akz5aNlqO+TJ0kqglkfnOsc
# jfKQzzDwcZthLVZl83igzCLnWMo8Zk/D2d4ZLY9esFwqPNvuuVDrHvgh7H6DJ/zP
# Vm5EOK0sljT0UQ6HQEwtouH5S8nrqCGZ8jKM/+DeJlm+rCAGGf7TV85uqsAn5JqD
# En/bXE1AlyG1Q5YiXFGS5Sf0qS4Nisw7vRrZ6Qc4NwBty4cAYjzDPDixorWI8+FV
# OUWKMdL7tV8i393/XykwsccCstBCp7VnSZN+4vgzjEJQql5uQfysjcW9rrb/qixp
# csPTKYRHMIIFMDCCBBigAwIBAgIQBAkYG1/Vu2Z1U0O1b5VQCDANBgkqhkiG9w0B
# AQsFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk
# IElEIFJvb3QgQ0EwHhcNMTMxMDIyMTIwMDAwWhcNMjgxMDIyMTIwMDAwWjByMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQg
# Q29kZSBTaWduaW5nIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
# +NOzHH8OEa9ndwfTCzFJGc/Q+0WZsTrbRPV/5aid2zLXcep2nQUut4/6kkPApfmJ
# 1DcZ17aq8JyGpdglrA55KDp+6dFn08b7KSfH03sjlOSRI5aQd4L5oYQjZhJUM1B0
# sSgmuyRpwsJS8hRniolF1C2ho+mILCCVrhxKhwjfDPXiTWAYvqrEsq5wMWYzcT6s
# cKKrzn/pfMuSoeU7MRzP6vIK5Fe7SrXpdOYr/mzLfnQ5Ng2Q7+S1TqSp6moKq4Tz
# rGdOtcT3jNEgJSPrCGQ+UpbB8g8S9MWOD8Gi6CxR93O8vYWxYoNzQYIH5DiLanMg
# 0A9kczyen6Yzqf0Z3yWT0QIDAQABo4IBzTCCAckwEgYDVR0TAQH/BAgwBgEB/wIB
# ADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwMweQYIKwYBBQUH
# AQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYI
# KwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFz
# c3VyZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmw0
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaG
# NGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RD
# QS5jcmwwTwYDVR0gBEgwRjA4BgpghkgBhv1sAAIEMCowKAYIKwYBBQUHAgEWHGh0
# dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwCgYIYIZIAYb9bAMwHQYDVR0OBBYE
# FFrEuXsqCqOl6nEDwGD5LfZldQ5YMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6en
# IZ3zbcgPMA0GCSqGSIb3DQEBCwUAA4IBAQA+7A1aJLPzItEVyCx8JSl2qB1dHC06
# GsTvMGHXfgtg/cM9D8Svi/3vKt8gVTew4fbRknUPUbRupY5a4l4kgU4QpO4/cY5j
# DhNLrddfRHnzNhQGivecRk5c/5CxGwcOkRX7uq+1UcKNJK4kxscnKqEpKBo6cSgC
# PC6Ro8AlEeKcFEehemhor5unXCBc2XGxDI+7qPjFEmifz0DLQESlE/DmZAwlCEIy
# sjaKJAL+L3J+HNdJRZboWR3p+nRka7LrZkPas7CM1ekN3fYBIM6ZMWM9CBoYs4Gb
# T8aTEAb8B4H6i9r5gkn3Ym6hU/oSlBiFLpKR6mhsRDKyZqHnGKSaZFHvMIIFMTCC
# BBmgAwIBAgIQCqEl1tYyG35B5AXaNpfCFTANBgkqhkiG9w0BAQsFADBlMQswCQYD
# VQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGln
# aWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0Ew
# HhcNMTYwMTA3MTIwMDAwWhcNMzEwMTA3MTIwMDAwWjByMQswCQYDVQQGEwJVUzEV
# MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29t
# MTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgVGltZXN0YW1waW5n
# IENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvdAy7kvNj3/dqbqC
# mcU5VChXtiNKxA4HRTNREH3Q+X1NaH7ntqD0jbOI5Je/YyGQmL8TvFfTw+F+CNZq
# FAA49y4eO+7MpvYyWf5fZT/gm+vjRkcGGlV+Cyd+wKL1oODeIj8O/36V+/OjuiI+
# GKwR5PCZA207hXwJ0+5dyJoLVOOoCXFr4M8iEA91z3FyTgqt30A6XLdR4aF5FMZN
# JCMwXbzsPGBqrC8HzP3w6kfZiFBe/WZuVmEnKYmEUeaC50ZQ/ZQqLKfkdT66mA+E
# f58xFNat1fJky3seBdCEGXIX8RcG7z3N1k3vBkL9olMqT4UdxB08r8/arBD13ays
# 6Vb/kwIDAQABo4IBzjCCAcowHQYDVR0OBBYEFPS24SAd/imu0uRhpbKiJbLIFzVu
# MB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHkGCCsG
# AQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29t
# MEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRBc3N1cmVkSURSb290Q0EuY3J0MIGBBgNVHR8EejB4MDqgOKA2hjRodHRwOi8v
# Y3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMDqg
# OKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURS
# b290Q0EuY3JsMFAGA1UdIARJMEcwOAYKYIZIAYb9bAACBDAqMCgGCCsGAQUFBwIB
# FhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAsGCWCGSAGG/WwHATANBgkq
# hkiG9w0BAQsFAAOCAQEAcZUS6VGHVmnN793afKpjerN4zwY3QITvS4S/ys8DAv3F
# p8MOIEIsr3fzKx8MIVoqtwU0HWqumfgnoma/Capg33akOpMP+LLR2HwZYuhegiUe
# xLoceywh4tZbLBQ1QwRostt1AuByx5jWPGTlH0gQGF+JOGFNYkYkh2OMkVIsrymJ
# 5Xgf1gsUpYDXEkdws3XVk4WTfraSZ/tTYYmo9WuWwPRYaQ18yAGxuSh1t5ljhSKM
# Ycp5lH5Z/IwP42+1ASa2bKXuh1Eh5Fhgm7oMLSttosR+u8QlK0cCCHxJrhO24XxC
# QijGGFbPQTS2Zl22dHv1VjMiLyI2skuiSpXY9aaOUjGCBFwwggRYAgEBMIGGMHIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJ
# RCBDb2RlIFNpZ25pbmcgQ0ECEAMFu4YhsKFjX7/erhIE520wCQYFKw4DAhoFAKB4
# MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQB
# gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkE
# MRYEFHUNNPE9GhQfQf+910gvkcXidWatMA0GCSqGSIb3DQEBAQUABIIBAKsfszJ9
# dRePmGjOKECbP6SbZuYBEG9HvEpcRI7NpoHpO/QzH7bLtFupbLHxgOPy2sG++fDR
# fCBlqVfSR1F5pC4tKLNdTvIAqIUKXntLTdH/+YhneI3wKHT9b+gb4r6ftfU7uy8C
# 23lXO/8dMk9oMbfnrfR0Yi0nFhjlSwe+diC3lDUuZTJ20RaGjnGte1DWCNK73HXc
# lVz/Xr2SjI4DRcYp3uq+8E77bv/McB5aBQ+YSfW+p+htvXy7W8+oJ7uC3L/TiA0q
# ixL+GV//dNIoAyqAVtHLP+pfbIYfT6Fxr30g+n/6tbIJHohZ/TRphd9t5l1BFAe3
# KiFkoNW7TiU9kM+hggIwMIICLAYJKoZIhvcNAQkGMYICHTCCAhkCAQEwgYYwcjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElE
# IFRpbWVzdGFtcGluZyBDQQIQDUJK4L46iP9gQCHOFADw3TANBglghkgBZQMEAgEF
# AKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIx
# MDczMDA4MDAxMFowLwYJKoZIhvcNAQkEMSIEIDlOJZHJ62/RPSqdhrNyEcfZiJuB
# +FQpHrBCNQ84boB8MA0GCSqGSIb3DQEBAQUABIIBAGmGjwWTIBCLOZvaNJI8d5j8
# 2NpN96pXPCUuYwV34Kd1alwAL4UqQ/IPSHqQDdTRUaqELF/j2Had2qEHVbHZ8j2s
# XEjVuG5lJTv7ftStQ2RraWNCjczuQLHL5UrX/KNubOumShNF5ec8JLlYv42UogJx
# kKnUwVIijO/Jj9UHxd874Agt3rlH3KyMRXCQccuoIZfzTcndXHgMtaez8m9Fdynx
# RudN5gYbDrytO7SvpsnFdXbwf0rfNi5pAvJiUd9zSGdGZCjMyLWyq0L9+kD/HzCo
# Rr9e9lugLt7Mn63U1otJAYxKO0eRO6jvZSkWOf7/tNALTRwmkVuyxSZncE2WkCA=
# SIG # End signature block
