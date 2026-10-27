# 키트 전용 예외. ExitCode 는 CLI 종료 코드: 1 사용법/권한, 2 가드 중단, 3 환경 문제, 4 미검증 버전 잠금.
if (-not ('KakaoKitException' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
public class KakaoKitException : Exception {
    public int ExitCode;
    public KakaoKitException(string message, int exitCode) : base(message) { ExitCode = exitCode; }
}
public class KakaoGuardException : KakaoKitException {
    public KakaoGuardException(string message) : base(message, 2) { }
}
public class KakaoClipboardException : KakaoKitException {
    public KakaoClipboardException(string message) : base(message, 3) { }
}
"@
}

# 한글 문구 사전의 키로 예외를 만든다. 사용: throw (New-KitError -Key 'error.xxx' -FormatArgs @(...) -ExitCode 1)
function New-KitError {
    param(
        [Parameter(Mandatory)][string]$Key,
        [object[]]$FormatArgs = @(),
        [int]$ExitCode = 1
    )
    return New-Object KakaoKitException -ArgumentList @((Get-Msg -Key $Key -FormatArgs $FormatArgs), $ExitCode)
}
