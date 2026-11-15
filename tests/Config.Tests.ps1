$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Config')
. (Join-Path $here '_Load.ps1')

Describe 'Config: 기본값과 저장' {
    Mock Test-InputRedirected { $false }

    It 'Get-KitConfig returns defaults when no file exists' {
        Use-TempHome {
            $c = Get-KitConfig
            $c.version | Should Be 1
            $c.consentAcceptedAt | Should BeNullOrEmpty
            $c.lastRoom | Should BeNullOrEmpty
            @($c.rooms).Count | Should Be 0
        }
    }

    It 'config.json is UTF-8 without BOM and keeps Korean names' {
        Use-TempHome {
            Add-AllowedRoom -Name '나와의 채팅' -Type 'self' -SelfOnly $true -Human
            $file = (Get-KitPaths).ConfigFile
            $b = [System.IO.File]::ReadAllBytes($file)
            ('{0:X2}{1:X2}' -f $b[0], $b[1]) | Should Not Be 'EFBB'
            [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8) | Should Match '나와의 채팅'
            @((Get-KitConfig).rooms)[0].name | Should Be '나와의 채팅'
        }
    }

    It 'a corrupt config.json throws a Korean error and is left untouched' {
        Use-TempHome {
            $p = Get-KitPaths
            New-Item -ItemType Directory -Path $p.DataDir -Force | Out-Null
            [System.IO.File]::WriteAllText($p.ConfigFile, '{ not json', (New-Object System.Text.UTF8Encoding($false)))
            $e = Get-ThrownError { Get-KitConfig }
            $e.ExitCode | Should Be 3
            $e.Message | Should Match '설정 파일'
            [System.IO.File]::ReadAllText($p.ConfigFile) | Should Be '{ not json'
        }
    }
}

Describe 'Config: 방 등록' {
    Mock Test-InputRedirected { $false }

    It 'an open room is verified, read+send on, AI switches off' {
        Use-TempHome {
            Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human
            $r = @((Get-KitConfig).rooms)[0]
            $r.name | Should Be '비밀방'
            $r.type | Should Be 'open'
            $r.verified | Should Be $true
            $r.canRead | Should Be $true
            $r.canSend | Should Be $true
            $r.selfOnly | Should Be $true
            $r.aiRead | Should Be $false
            $r.aiSend | Should Be $false
        }
    }

    It 'a normal (friend) room is unverified and read-only' {
        Use-TempHome {
            Add-AllowedRoom -Name '친구방' -Type 'normal' -SelfOnly $false -Human
            $r = @((Get-KitConfig).rooms)[0]
            $r.verified | Should Be $false
            $r.canRead | Should Be $true
            $r.canSend | Should Be $false
            $r.selfOnly | Should Be $false
        }
    }

    It 'rejects bad names, duplicate names and unknown types' {
        Use-TempHome {
            (Get-ThrownError { Add-AllowedRoom -Name '' -Type 'open' -SelfOnly $true -Human }).ExitCode | Should Be 1
            (Get-ThrownError { Add-AllowedRoom -Name ' 비밀방' -Type 'open' -SelfOnly $true -Human }).ExitCode | Should Be 1
            (Get-ThrownError { Add-AllowedRoom -Name "비밀`n방" -Type 'open' -SelfOnly $true -Human }).ExitCode | Should Be 1
            (Get-ThrownError { Add-AllowedRoom -Name '방' -Type 'group' -SelfOnly $true -Human }).ExitCode | Should Be 1
            Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human
            $dup = Get-ThrownError { Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human }
            $dup.ExitCode | Should Be 1
            $dup.Message | Should Match '이미 등록'
            @((Get-KitConfig).rooms).Count | Should Be 1
        }
    }

    It 'Remove-AllowedRoom deletes only the named room' {
        Use-TempHome {
            Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human
            Add-AllowedRoom -Name '나와의 채팅' -Type 'self' -SelfOnly $true -Human
            Remove-AllowedRoom -Name '비밀방' -Human
            $names = @((Get-KitConfig).rooms | ForEach-Object { $_.name })
            $names.Count | Should Be 1
            $names[0] | Should Be '나와의 채팅'
            (Get-ThrownError { Remove-AllowedRoom -Name '없는방' -Human }).ExitCode | Should Be 1
        }
    }
}

Describe 'Config: 방 이름은 정확히 일치해야 허용' {
    Mock Test-InputRedirected { $false }

    It 'matches the room name exactly (no trim, no prefix)' {
        Use-TempHome {
            Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human
            Test-RoomAllowed -Name '비밀방' -Action read -Caller human | Should Be $true
            Test-RoomAllowed -Name '비밀방 ' -Action read -Caller human | Should Be $false
            Test-RoomAllowed -Name ' 비밀방' -Action read -Caller human | Should Be $false
            Test-RoomAllowed -Name '비밀' -Action read -Caller human | Should Be $false
            Test-RoomAllowed -Name '비밀방2' -Action read -Caller human | Should Be $false
            Test-RoomAllowed -Name '' -Action read -Caller human | Should Be $false
        }
    }

    It 'is case-sensitive' {
        Use-TempHome {
            Add-AllowedRoom -Name 'Room A' -Type 'open' -SelfOnly $true -Human
            Test-RoomAllowed -Name 'Room A' -Action read -Caller human | Should Be $true
            Test-RoomAllowed -Name 'room a' -Action read -Caller human | Should Be $false
        }
    }

    # PowerShell 5.1 의 -ceq 는 문화권 비교라 너비 0 글자·소프트 하이픈·BOM 을 무시한다. 허용 목록 조회는 글자 그대로(Ordinal) 비교해야 한다.
    It 'does not match a name that differs only by an invisible character (zero-width, soft hyphen, BOM, bidi)' {
        Use-TempHome {
            Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human
            foreach ($cp in 0x200D, 0x00AD, 0xFEFF, 0x200B, 0x202E) {
                $fake = '비밀' + [string][char]$cp + '방'
                Test-RoomAllowed -Name $fake -Action read -Caller human | Should Be $false
                Test-RoomAllowed -Name $fake -Action send -Caller human | Should Be $false
                Find-Room -Config (Get-KitConfig) -Name $fake | Should BeNullOrEmpty
            }
            $e = Get-ThrownError { Remove-AllowedRoom -Name ('비밀' + [string][char]0x200D + '방') -Human }
            $e.ExitCode | Should Be 1
            Test-RoomAllowed -Name '비밀방' -Action read -Caller human | Should Be $true
        }
    }

    It 'fails closed on unknown actions and callers' {
        Use-TempHome {
            Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human
            Test-RoomAllowed -Name '비밀방' -Action delete -Caller human | Should Be $false
            Test-RoomAllowed -Name '비밀방' -Action read -Caller robot | Should Be $false
        }
    }
}

Describe 'Config: 권한 스위치' {
    Mock Test-InputRedirected { $false }

    It 'AI callers need aiRead/aiSend, which start off' {
        Use-TempHome {
            Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human
            Test-RoomAllowed -Name '비밀방' -Action read -Caller ai | Should Be $false
            Test-RoomAllowed -Name '비밀방' -Action send -Caller ai | Should Be $false
            Set-RoomPermission -Name '비밀방' -Permission aiRead -Value $true -Human
            Test-RoomAllowed -Name '비밀방' -Action read -Caller ai | Should Be $true
            Test-RoomAllowed -Name '비밀방' -Action send -Caller ai | Should Be $false
            Set-RoomPermission -Name '비밀방' -Permission aiSend -Value $true -Human
            Test-RoomAllowed -Name '비밀방' -Action send -Caller ai | Should Be $true
            Test-RoomAllowed -Name '비밀방' -Action send -Caller human | Should Be $true
        }
    }

    It 'canSend=false blocks sending for humans too' {
        Use-TempHome {
            Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human
            Set-RoomPermission -Name '비밀방' -Permission canSend -Value $false -Human
            Test-RoomAllowed -Name '비밀방' -Action send -Caller human | Should Be $false
            Test-RoomAllowed -Name '비밀방' -Action read -Caller human | Should Be $true
        }
    }

    It 'sending to a normal (unverified) room needs -AllowUnverifiedRoom, and never works for AI' {
        Use-TempHome {
            Add-AllowedRoom -Name '친구방' -Type 'normal' -SelfOnly $false -Human
            Test-RoomAllowed -Name '친구방' -Action read -Caller human | Should Be $true
            Test-RoomAllowed -Name '친구방' -Action send -Caller human | Should Be $false
            Set-RoomPermission -Name '친구방' -Permission canSend -Value $true -Human
            Test-RoomAllowed -Name '친구방' -Action send -Caller human | Should Be $false
            Test-RoomAllowed -Name '친구방' -Action send -Caller human -AllowUnverifiedRoom | Should Be $true
            Set-RoomPermission -Name '친구방' -Permission aiSend -Value $true -Human
            Test-RoomAllowed -Name '친구방' -Action send -Caller ai -AllowUnverifiedRoom | Should Be $false
        }
    }

    It 'rejects an unknown permission name and an unknown room' {
        Use-TempHome {
            Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human
            (Get-ThrownError { Set-RoomPermission -Name '비밀방' -Permission admin -Value $true -Human }).ExitCode | Should Be 1
            (Get-ThrownError { Set-RoomPermission -Name '없는방' -Permission aiRead -Value $true -Human }).ExitCode | Should Be 1
        }
    }
}

Describe 'Config: 사람만 바꿀 수 있다' {
    Mock Test-InputRedirected { $false }

    It 'Add-AllowedRoom without -Human throws and writes nothing' {
        Use-TempHome {
            $e = Get-ThrownError { Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true }
            $e.ExitCode | Should Be 1
            Test-Path (Get-KitPaths).ConfigFile | Should Be $false
        }
    }

    It 'Set-RoomPermission, Remove-AllowedRoom and Set-KitConsent without -Human change nothing' {
        Use-TempHome {
            Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human
            (Get-ThrownError { Set-RoomPermission -Name '비밀방' -Permission aiRead -Value $true }).ExitCode | Should Be 1
            (Get-ThrownError { Remove-AllowedRoom -Name '비밀방' }).ExitCode | Should Be 1
            (Get-ThrownError { Set-KitConsent }).ExitCode | Should Be 1
            $r = @((Get-KitConfig).rooms)[0]
            $r.aiRead | Should Be $false
            Test-KitConsent | Should Be $false
        }
    }
}

Describe 'Config: 입력이 막힌 곳(자동 실행)에서는 사람 작업도 거부' {
    Mock Test-InputRedirected { $true }

    It 'Add-AllowedRoom -Human is refused when stdin is redirected' {
        Use-TempHome {
            $e = Get-ThrownError { Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human }
            $e.ExitCode | Should Be 1
            $e.Message | Should Match '키보드'
            Test-Path (Get-KitPaths).ConfigFile | Should Be $false
        }
    }

    It 'Set-KitConsent -Human is refused when stdin is redirected' {
        Use-TempHome {
            (Get-ThrownError { Set-KitConsent -Human }).ExitCode | Should Be 1
            Test-KitConsent | Should Be $false
        }
    }
}

Describe 'Config: 동의' {
    Mock Test-InputRedirected { $false }

    It 'Assert-KitReady throws before consent and passes after Set-KitConsent' {
        Use-TempHome {
            $e = Get-ThrownError { Assert-KitReady }
            $e.ExitCode | Should Be 1
            $e.Message | Should Match '동의'
            Test-KitConsent | Should Be $false
            Set-KitConsent -Human
            Test-KitConsent | Should Be $true
            { Assert-KitReady } | Should Not Throw
        }
    }

    # 손으로 고친 false·0·"no" 는 동의가 아니다(글자로 바꾸면 비어 있지 않아 통과해 버리던 구멍).
    It 'a consentAcceptedAt that is not a real date (false, 0, "no", [], {}) never counts as consent' {
        Use-TempHome {
            $p = Get-KitPaths
            New-Item -ItemType Directory -Path $p.DataDir -Force | Out-Null
            foreach ($bad in 'false', 'true', '0', '1', '"no"', '"yes"', '"  "', '[]', '{}', '"2026-13-45T99:00:00"') {
                [System.IO.File]::WriteAllText($p.ConfigFile, ('{"version":1,"consentAcceptedAt":' + $bad + ',"rooms":[]}'), (New-Object System.Text.UTF8Encoding($false)))
                Test-KitConsent | Should Be $false
                (Get-ThrownError { Assert-KitReady }).ExitCode | Should Be 1
            }
            [System.IO.File]::WriteAllText($p.ConfigFile, '{"version":1,"consentAcceptedAt":"2026-10-27T13:30:00","rooms":[]}', (New-Object System.Text.UTF8Encoding($false)))
            Test-KitConsent | Should Be $true
        }
    }
}

Describe 'Config: 손으로 고친 설정 파일 (이상한 값은 항상 거부 쪽으로)' {
    Mock Test-InputRedirected { $false }

    function Write-RawConfig([string]$Json) {
        $p = Get-KitPaths
        New-Item -ItemType Directory -Path $p.DataDir -Force | Out-Null
        [System.IO.File]::WriteAllText($p.ConfigFile, $Json, (New-Object System.Text.UTF8Encoding($false)))
    }
    function New-RoomJson([string]$Fields) {
        return ('{"version":1,"rooms":[{"name":"비밀방","type":"open",' + $Fields + '}]}')
    }
    $badFlags = '"true"', '1', '[true]', '"yes"', 'null', '{}'

    It 'only a real JSON true grants read access (strings, numbers, arrays never do)' {
        Use-TempHome {
            foreach ($bad in $badFlags) {
                Write-RawConfig (New-RoomJson ('"verified":true,"canRead":' + $bad + ',"canSend":true,"selfOnly":true,"aiRead":true,"aiSend":true'))
                Test-RoomAllowed -Name '비밀방' -Action read -Caller human | Should Be $false
            }
            Write-RawConfig (New-RoomJson '"verified":true,"canRead":true,"canSend":true,"selfOnly":true,"aiRead":false,"aiSend":false')
            Test-RoomAllowed -Name '비밀방' -Action read -Caller human | Should Be $true
        }
    }

    It 'only a real JSON true grants send access' {
        Use-TempHome {
            foreach ($bad in $badFlags) {
                Write-RawConfig (New-RoomJson ('"verified":true,"canRead":true,"canSend":' + $bad + ',"selfOnly":true,"aiRead":true,"aiSend":true'))
                Test-RoomAllowed -Name '비밀방' -Action send -Caller human | Should Be $false
            }
        }
    }

    It 'AI access needs a real JSON true in aiRead / aiSend' {
        Use-TempHome {
            foreach ($bad in $badFlags) {
                Write-RawConfig (New-RoomJson ('"verified":true,"canRead":true,"canSend":true,"selfOnly":true,"aiRead":' + $bad + ',"aiSend":true'))
                Test-RoomAllowed -Name '비밀방' -Action read -Caller ai | Should Be $false
                Write-RawConfig (New-RoomJson ('"verified":true,"canRead":true,"canSend":true,"selfOnly":true,"aiRead":true,"aiSend":' + $bad))
                Test-RoomAllowed -Name '비밀방' -Action send -Caller ai | Should Be $false
            }
        }
    }

    It 'a friend room is not treated as verified unless verified is a real JSON true' {
        Use-TempHome {
            foreach ($bad in '"true"', '1', '[true]') {
                Write-RawConfig ('{"version":1,"rooms":[{"name":"비밀방","type":"normal","verified":' + $bad + ',"canRead":true,"canSend":true,"selfOnly":false,"aiRead":true,"aiSend":true}]}')
                Test-RoomAllowed -Name '비밀방' -Action send -Caller human | Should Be $false
                Test-RoomAllowed -Name '비밀방' -Action send -Caller ai -AllowUnverifiedRoom | Should Be $false
            }
        }
    }

    It 'a config that is not a JSON object is reported as corrupt (exit 3), never silently accepted' {
        Use-TempHome {
            foreach ($bad in '[]', '"hello"', '123', 'true', 'null', '') {
                Write-RawConfig $bad
                $e = Get-ThrownError { Get-KitConfig }
                $e.ExitCode | Should Be 3
                $e.Message | Should Match '설정 파일'
            }
        }
    }

    It 'saving fails with a Korean error (exit 3) instead of a raw system error' {
        Use-TempHome {
            [System.IO.File]::WriteAllText($env:KAKAO_KIT_HOME, 'x')
            $e = Get-ThrownError { Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human }
            $e.GetType().Name | Should Be 'KakaoKitException'
            $e.ExitCode | Should Be 3
            $e.Message | Should Match '저장'
        }
    }

    # 손으로 고쳐 같은 이름이 둘이 되면 보내기·읽기는 거부(안전)된다. 그래도 지우는 것은(권한을 줄이는 방향) 막지 않는다.
    It 'duplicate room names are refused for use, but Remove-AllowedRoom can still clean them up' {
        Use-TempHome {
            $r = '{"name":"비밀방","type":"open","verified":true,"canRead":true,"canSend":true,"selfOnly":true,"aiRead":false,"aiSend":false}'
            Write-RawConfig ('{"version":1,"rooms":[' + $r + ',' + $r + ']}')
            Test-RoomAllowed -Name '비밀방' -Action read -Caller human | Should Be $false
            Remove-AllowedRoom -Name '비밀방' -Human
            @(Get-ConfigRooms -Config (Get-KitConfig)).Count | Should Be 0
        }
    }

    It 'room names: invisible characters and names over 100 characters are rejected' {
        Use-TempHome {
            $zeroWidth = '방' + [char]0x200B + 'A'
            $bom = '방' + [char]0xFEFF
            $rtl = '방' + [char]0x202E + 'A'
            foreach ($bad in $zeroWidth, $bom, $rtl, ('가' * 101)) {
                (Get-ThrownError { Add-AllowedRoom -Name $bad -Type 'open' -SelfOnly $true -Human }).ExitCode | Should Be 1
            }
            { Add-AllowedRoom -Name ('가' * 100) -Type 'open' -SelfOnly $true -Human } | Should Not Throw
        }
    }
}

Describe 'Config: 검증된 카카오톡 버전' {
    It 'Get-VerifiedKakaoVersions lists 26.9.0.5337' {
        (@(Get-VerifiedKakaoVersions) -contains '26.9.0.5337') | Should Be $true
    }
}


Describe 'Config: 초안 없음 표시(noDraft)' {
    Mock Test-InputRedirected { $false }

    It 'a new room starts with noDraft off' {
        Use-TempHome {
            Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human
            @((Get-KitConfig).rooms)[0].noDraft | Should Be $false
        }
    }

    It 'only a person can switch it, and it is a valid permission name' {
        Use-TempHome {
            Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human
            (Get-ThrownError { Set-RoomPermission -Name '비밀방' -Permission noDraft -Value $true }).ExitCode | Should Be 1
            Test-RoomNoDraft -Name '비밀방' | Should Be $false
            Set-RoomPermission -Name '비밀방' -Permission noDraft -Value $true -Human
            Test-RoomNoDraft -Name '비밀방' | Should Be $true
            Set-RoomPermission -Name '비밀방' -Permission noDraft -Value $false -Human
            Test-RoomNoDraft -Name '비밀방' | Should Be $false
        }
    }

    It 'is false for unknown rooms, a missing field and non-boolean values' {
        Use-TempHome {
            Test-RoomNoDraft -Name '없는방' | Should Be $false
            foreach ($bad in '"true"', '1', 'null', '[true]') {
                $p = Get-KitPaths
                New-Item -ItemType Directory -Path $p.DataDir -Force | Out-Null
                [System.IO.File]::WriteAllText($p.ConfigFile, ('{"version":1,"rooms":[{"name":"비밀방","type":"open","verified":true,"canRead":true,"canSend":true,"selfOnly":true,"aiRead":false,"aiSend":false,"noDraft":' + $bad + '}]}'), (New-Object System.Text.UTF8Encoding($false)))
                Test-RoomNoDraft -Name '비밀방' | Should Be $false
            }
            [System.IO.File]::WriteAllText((Get-KitPaths).ConfigFile, '{"version":1,"rooms":[{"name":"비밀방","type":"open","verified":true,"canRead":true,"canSend":true,"selfOnly":true,"aiRead":false,"aiSend":false}]}', (New-Object System.Text.UTF8Encoding($false)))
            Test-RoomNoDraft -Name '비밀방' | Should Be $false
        }
    }

    It 'still rejects a permission name that does not exist' {
        Use-TempHome {
            Add-AllowedRoom -Name '비밀방' -Type 'open' -SelfOnly $true -Human
            (Get-ThrownError { Set-RoomPermission -Name '비밀방' -Permission draftFree -Value $true -Human }).ExitCode | Should Be 1
        }
    }
}