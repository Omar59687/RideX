<#
.SYNOPSIS
  Local-only, actor-authenticated retirement of the historical R06 Card Trip.

.DESCRIPTION
  Reads the app's ignored .env.json, prompts for both actor passwords with
  hidden input, validates short-lived Supabase Auth sessions, then uses a
  separately prompted service_role key only for allowlisted read-only evidence
  collection. Rider and Driver mutations always use their own actor sessions.
  No SQL, token/password persistence, or provider call is used.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'

$script:R06ProjectUrl = 'https://ykasivejjchupswqyxpm.supabase.co'
$script:R06ProjectRef = 'ykasivejjchupswqyxpm'
$script:R06TripId = 'ceff7eb6-2d1f-4744-9cbc-243d80d550ba'
$script:R06RiderEmail = 'yousufrider@gmail.com'
$script:R06DriverEmail = 'yousufdriver@gmail.com'
$script:R06VehicleId = '48d007ab-c13c-4ff8-93f3-1dc7f1e6975d'
$script:R06Namespace = 'ridex-grad-ykasivejjchupswqyxpm-v1'
$script:R06AttemptWindowSeconds = 120
$script:R06HttpTransport = $null

function Get-R06Rows($Value) {
  if ($null -eq $Value) { return ,@() }
  if ($Value -is [System.Array]) { return ,$Value }
  return ,@($Value)
}

function ConvertFrom-R06ReservationResponse {
  param([AllowNull()][object]$Response)
  if ($null -eq $Response) { return $null }
  if ($Response -isnot [string] -or [string]::IsNullOrWhiteSpace($Response)) {
    throw 'reservation_response_invalid'
  }
  $json = $Response.Trim()
  if ($json -ceq 'null') { return $null }
  # Check the JSON root before ConvertFrom-Json can enumerate arrays into the
  # PowerShell pipeline (notably on PowerShell 7).
  if (-not $json.StartsWith('{', [StringComparison]::Ordinal)) {
    throw 'reservation_response_invalid'
  }
  try { $parsed = ConvertFrom-Json -InputObject $json -ErrorAction Stop }
  catch { throw 'reservation_response_invalid' }
  if ($null -eq $parsed -or $parsed -isnot [pscustomobject]) {
    throw 'reservation_response_invalid'
  }
  return $parsed
}

function Assert-R06ReservationAbsent {
  param([AllowNull()][object]$Reservation, [string]$ConflictCode = 'reservation_conflict')
  if ($null -eq $Reservation) { return }
  $properties = @{}
  if ($Reservation -is [System.Collections.IDictionary]) {
    foreach ($name in @('disposition','state','context','reference')) {
      if ($Reservation.Contains($name)) { $properties[$name] = $Reservation[$name] }
    }
  } elseif ($Reservation -is [pscustomobject]) {
    foreach ($name in @('disposition','state','context','reference')) {
      if ($Reservation.PSObject.Properties[$name]) { $properties[$name] = $Reservation.$name }
    }
  }
  if ($properties.Count -eq 4 -and $properties.disposition -ceq 'existing' -and
      $properties.state -cin @('reserved','unknown','prepared') -and $null -ne $properties.context) {
    throw $ConflictCode
  }
  throw 'reservation_response_invalid'
}

function Invoke-R06Http {
  param(
    [Parameter(Mandatory)][ValidateSet('GET','POST')][string]$Method,
    [Parameter(Mandatory)][string]$Uri,
    [Parameter(Mandatory)][hashtable]$Headers,
    [AllowNull()][object]$Body
  )
  $arguments = $null
  try {
    $isReservationRead = $Uri -ceq ($script:R06ProjectUrl + '/rest/v1/rpc/backend_read_stripe_test_preparation')
    if ($script:R06HttpTransport) {
      $response = & $script:R06HttpTransport $Method $Uri $Headers $Body
      if ($isReservationRead) { return ConvertFrom-R06ReservationResponse -Response $response }
      return $response
    }
    $arguments = @{
      Method = $Method
      Uri = $Uri
      Headers = $Headers
      TimeoutSec = 10
      MaximumRedirection = 0
      ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
      $arguments.ContentType = 'application/json'
      $arguments.Body = ConvertTo-Json -InputObject $Body -Depth 8 -Compress
    }
    if ($isReservationRead) {
      $arguments.UseBasicParsing = $true
      $response = Invoke-WebRequest @arguments
      $contentType = [string]$response.Headers['Content-Type']
      if ($contentType -notmatch '^application/json(?:\s*;|$)') { throw 'reservation_response_invalid' }
      return ConvertFrom-R06ReservationResponse -Response ([string]$response.Content)
    }
    return Invoke-RestMethod @arguments
  } catch {
    # Never surface HTTP exception details: providers and proxies can echo
    # request material. The caller decides whether this is an allowed absence.
    $failure = [System.Exception]::new('r06_request_failed')
    $code = $null
    try {
      $responseBody = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop
      $code = [string]$responseBody.code
    } catch { }
    $responseBody = $null
    $failure.Data['R06Code'] = if ($code -ceq 'P0002') { 'not_found' }
      elseif ($code -ceq '42501') { 'permission_denied' }
      else { 'request_failed' }
    throw $failure
  } finally {
    $Headers.Authorization = $null
    if ($arguments) { $arguments.Body = $null }
    $Body = $null
  }
}

function Get-R06JwtPayload {
  param([Parameter(Mandatory)][string]$Token)
  $parts = $Token.Split('.')
  if ($parts.Count -ne 3) { throw 'session_invalid' }
  try {
    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) {
      2 { $payload += '==' }
      3 { $payload += '=' }
      1 { throw 'session_invalid' }
    }
    $bytes = [Convert]::FromBase64String($payload)
    return [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop
  } catch { throw 'session_invalid' }
}

function Convert-R06SecureString {
  param([Parameter(Mandatory)][Security.SecureString]$Value)
  $pointer = [IntPtr]::Zero
  try {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  } finally {
    if ($pointer -ne [IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
  }
}

function Get-R06Configuration {
  $path = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) '.env.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw 'local_config_missing'
  }
  $jsonText = $null
  $config = $null
  try {
    $jsonText = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
    $config = $jsonText | ConvertFrom-Json -ErrorAction Stop
    $url = [string]$config.SUPABASE_URL
    $key = [string]$config.SUPABASE_PUBLISHABLE_KEY
  } catch { throw 'local_config_invalid' }
  finally {
    $jsonText = $null
    if ($config -and $config.PSObject.Properties['GOOGLE_MAPS_API_KEY']) { $config.GOOGLE_MAPS_API_KEY = $null }
    if ($config -and $config.PSObject.Properties['SUPABASE_PUBLISHABLE_KEY']) { $config.SUPABASE_PUBLISHABLE_KEY = $null }
    if ($config -and $config.PSObject.Properties['SUPABASE_URL']) { $config.SUPABASE_URL = $null }
    $config = $null
  }
  if ($url -cne $script:R06ProjectUrl -or [string]::IsNullOrWhiteSpace($key)) {
    throw 'project_config_mismatch'
  }
  $result = @{ Url = $url; Key = $key }
  $url = $null
  $key = $null
  return $result
}

function Invoke-R06Request {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$ApiKey,
    [Parameter(Mandatory)][string]$Token,
    [ValidateSet('GET','POST')][string]$Method = 'GET',
    [AllowNull()][object]$Body
  )
  $headers = @{
    apikey = $ApiKey
    Authorization = "Bearer $Token"
    Accept = 'application/json'
  }
  return Invoke-R06Http -Method $Method -Uri ($script:R06ProjectUrl + $Path) -Headers $headers -Body $Body
}

function Assert-R06OperatorKey {
  param([Parameter(Mandatory)][Security.SecureString]$OperatorKey)
  $plainKey = $null; $payload = $null
  try {
    $plainKey = Convert-R06SecureString $OperatorKey
    $payload = Get-R06JwtPayload $plainKey
    $issuer = $payload.PSObject.Properties['iss']
    $projectRef = $payload.PSObject.Properties['ref']
    $role = $payload.PSObject.Properties['role']
    $expiry = $payload.PSObject.Properties['exp']
    if (-not $issuer -or -not $projectRef -or -not $role -or -not $expiry -or
        $issuer.Value -isnot [string] -or $projectRef.Value -isnot [string] -or
        $role.Value -isnot [string] -or
        ($expiry.Value -isnot [int] -and $expiry.Value -isnot [long]) -or
        $issuer.Value -cne 'supabase' -or
        $projectRef.Value -cne $script:R06ProjectRef -or
        $role.Value -cne 'service_role' -or
        [long]$expiry.Value -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) {
      throw 'operator_credential_invalid'
    }
  } catch {
    # Local JWT decoding is a shape/claim check, not signature verification.
    # The allowlisted read-only API preflight below authenticates the key with
    # Supabase before either actor mutation can be reached.
    throw 'operator_credential_invalid'
  } finally {
    $plainKey = $null
    if ($payload) { $payload = $null }
  }
}

function Invoke-R06OperatorRead {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][Security.SecureString]$OperatorKey,
    [AllowNull()][object]$Body
  )
  $method = 'GET'
  if ($Path -ceq '/rest/v1/rpc/backend_read_stripe_test_preparation') {
    $method = 'POST'
  } elseif ($Path -notmatch '^/rest/v1/(trips|payments|payment_attempts|receipts|driver_availability|vehicles)\?') {
    throw 'operator_read_path_not_allowed'
  }
  $plainKey = $null
  $headers = $null
  try {
    $plainKey = Convert-R06SecureString $OperatorKey
    $headers = @{ apikey = $plainKey; Authorization = "Bearer $plainKey"; Accept = 'application/json' }
    return Invoke-R06Http -Method $method -Uri ($script:R06ProjectUrl + $Path) -Headers $headers -Body $Body
  } finally {
    if ($headers) { $headers.Authorization = $null; $headers.apikey = $null }
    $plainKey = $null
    $Body = $null
  }
}

function Get-R06Actor {
  param(
    [Parameter(Mandatory)][ValidateSet('rider','driver')][string]$Kind,
    [Parameter(Mandatory)][string]$Email,
    [Parameter(Mandatory)][Security.SecureString]$Password,
    [Parameter(Mandatory)][string]$AnonKey
  )
  $plainPassword = $null
  $authResponse = $null
  $authRequest = $null
  try {
    $plainPassword = Convert-R06SecureString $Password
    $authRequest = @{ email = $Email; password = $plainPassword }
    $authHeaders = @{ apikey = $AnonKey; Accept = 'application/json' }
    $authResponse = Invoke-R06Http -Method POST -Uri ($script:R06ProjectUrl + '/auth/v1/token?grant_type=password') -Headers $authHeaders -Body $authRequest
    $token = [string]$authResponse.access_token
  } finally {
    if ($authRequest) { $authRequest.password = $null }
    $plainPassword = $null
    $Password.Dispose()
  }
  if ([string]::IsNullOrWhiteSpace($token)) { throw 'authentication_failed' }

  $payload = Get-R06JwtPayload $token
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  if ($payload.iss -cne ($script:R06ProjectUrl + '/auth/v1') -or
      $payload.role -cne 'authenticated' -or
      [string]$payload.sub -notmatch '^[0-9a-fA-F-]{36}$' -or
      [long]$payload.exp -le $now -or
      ([long]$payload.exp - $now) -gt 86400) {
    $token = $null
    throw 'session_invalid'
  }
  $authResponse = $null # discard the response, including refresh token
  $verified = Invoke-R06Request -Path '/auth/v1/user' -ApiKey $AnonKey -Token $token
  if ([string]$verified.id -cne [string]$payload.sub -or
      ([string]$verified.email).ToLowerInvariant() -cne $Email) {
    $token = $null
    throw 'actor_identity_mismatch'
  }
  $profileRows = Get-R06Rows (Invoke-R06Request -Path "/rest/v1/users?select=id,email,role,is_blocked&id=eq.$($verified.id)&limit=2" -ApiKey $AnonKey -Token $token)
  if ($profileRows.Count -ne 1 -or $profileRows[0].id -cne $verified.id -or
      ([string]$profileRows[0].email).ToLowerInvariant() -cne $Email -or
      $profileRows[0].role -cne $Kind -or $profileRows[0].is_blocked -ne $false) {
    $token = $null
    throw 'actor_role_or_profile_mismatch'
  }
  if ($Kind -eq 'driver') {
    $driverRows = Get-R06Rows (Invoke-R06Request -Path "/rest/v1/driver_profiles?select=user_id,approval_status&user_id=eq.$($verified.id)&limit=2" -ApiKey $AnonKey -Token $token)
    if ($driverRows.Count -ne 1 -or $driverRows[0].user_id -cne $verified.id -or $driverRows[0].approval_status -cne 'approved') {
      $token = $null
      throw 'driver_approval_mismatch'
    }
  }
  $actor = @{ Id = [string]$verified.id; Email = $Email; Token = $token; ExpiresAt = [long]$payload.exp }
  $token = $null
  $payload = $null
  return $actor
}

function Assert-R06ActorSession {
  param([hashtable]$Actor, [string]$AnonKey)
  if ([long]$Actor.ExpiresAt -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) { throw 'session_expired_stop' }
  $verified = Invoke-R06Request -Path '/auth/v1/user' -ApiKey $AnonKey -Token $Actor.Token
  if ([string]$verified.id -cne $Actor.Id -or ([string]$verified.email).ToLowerInvariant() -cne $Actor.Email) {
    throw 'session_identity_changed_stop'
  }
}

function Invoke-R06Rpc {
  param([string]$Name, [string]$Token, [string]$AnonKey, [hashtable]$Body)
  return Invoke-R06Request -Path "/rest/v1/rpc/$Name" -ApiKey $AnonKey -Token $Token -Method POST -Body $Body
}

function Get-R06Preflight {
  param([hashtable]$Rider, [hashtable]$Driver, [string]$AnonKey, [Security.SecureString]$OperatorKey)
  $tripRows = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/trips?select=id,booking_request_id,rider_id,driver_id,vehicle_id,payment_method,status,version,currency,original_fare_fils,current_fare_fils&id=eq.$($script:R06TripId)&limit=2" -OperatorKey $OperatorKey -Body $null)
  if ($tripRows.Count -ne 1) { throw 'trip_preflight_failed' }
  $trip = $tripRows[0]
  if ($trip.id -cne $script:R06TripId -or $trip.rider_id -cne $Rider.Id -or
      $trip.driver_id -cne $Driver.Id -or $trip.vehicle_id -cne $script:R06VehicleId -or
      $trip.payment_method -cne 'card' -or $trip.status -cne 'accepted' -or
      [int]$trip.version -lt 1 -or $trip.currency -cne 'JOD' -or
      [int]$trip.current_fare_fils -lt 1 -or
      [int]$trip.original_fare_fils -ne [int]$trip.current_fare_fils) {
    throw 'trip_preflight_mismatch'
  }
  $activeStatuses = 'in.(accepted,driverArriving,driverArrived,inProgress)'
  $riderActive = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/trips?select=id,rider_id,status&rider_id=eq.$($Rider.Id)&status=$activeStatuses&limit=3" -OperatorKey $OperatorKey -Body $null)
  $driverActive = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/trips?select=id,driver_id,status&driver_id=eq.$($Driver.Id)&status=$activeStatuses&limit=3" -OperatorKey $OperatorKey -Body $null)
  if ($riderActive.Count -ne 1 -or $driverActive.Count -ne 1 -or
      $riderActive[0].id -cne $script:R06TripId -or $driverActive[0].id -cne $script:R06TripId) {
    throw 'active_trip_conflict'
  }
  $paymentRows = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/payments?select=id,trip_id,rider_id,method,final_amount_fils,authorized_amount_fils,currency,card_status,version,authorized_at,paid_at,cancelled_at,refunded_at&trip_id=eq.$($script:R06TripId)&limit=2" -OperatorKey $OperatorKey -Body $null)
  if ($paymentRows.Count -ne 1) { throw 'payment_preflight_failed' }
  $payment = $paymentRows[0]
  if ($payment.trip_id -cne $script:R06TripId -or $payment.rider_id -cne $Rider.Id -or
      $payment.method -cne 'card' -or $payment.card_status -cne 'cardPaymentPending' -or
      [int]$payment.version -lt 1 -or $payment.currency -cne 'JOD' -or
      [int]$payment.final_amount_fils -ne [int]$trip.current_fare_fils -or
      $null -ne $payment.authorized_at -or $null -ne $payment.paid_at -or
      $null -ne $payment.cancelled_at -or $null -ne $payment.refunded_at -or
      [int]$payment.authorized_amount_fils -ne [int]$trip.original_fare_fils) {
    throw 'payment_preflight_mismatch'
  }
  $attempts = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/payment_attempts?select=id,payment_id,type,status,authorization_cycle,attempt_sequence,provider_name,idempotency_key,requested_amount_fils,currency,provider_transaction_reference,sanitized_failure_code,sanitized_failure_message,completed_at,verified_at,refund_id,created_at&payment_id=eq.$($payment.id)&limit=2" -OperatorKey $OperatorKey -Body $null)
  if ($attempts.Count -ne 1 -or $attempts[0].type -cne 'initialAuthorization' -or
      $attempts[0].status -cne 'pending' -or [int]$attempts[0].authorization_cycle -ne 1 -or
      $attempts[0].provider_name -cne 'stripe' -or
      $null -ne $attempts[0].completed_at -or $null -ne $attempts[0].verified_at -or
      $attempts[0].currency -cne 'JOD' -or [int]$attempts[0].requested_amount_fils -ne [int]$trip.current_fare_fils -or
      (([DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse([string]$attempts[0].created_at).ToUniversalTime()).TotalSeconds -le $script:R06AttemptWindowSeconds)) {
    throw 'attempt_preflight_mismatch'
  }
  $attempt = $attempts[0]
  $attemptRows = $attempts
  if ($attemptRows.Count -ne 1 -or $attemptRows[0].id -cne $attempt.id -or
      $attemptRows[0].payment_id -cne $payment.id -or
      $null -ne $attemptRows[0].provider_transaction_reference -or
      $attemptRows[0].status -cne 'pending' -or $null -ne $attemptRows[0].completed_at) {
    throw 'attempt_provider_evidence_unavailable_or_conflicting'
  }
  $reservation = Invoke-R06OperatorRead -Path '/rest/v1/rpc/backend_read_stripe_test_preparation' -OperatorKey $OperatorKey -Body @{ target_attempt_id = $attempt.id; actor_rider_id = $Rider.Id }
  Assert-R06ReservationAbsent -Reservation $reservation
  $receiptRows = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/receipts?select=id&trip_id=eq.$($script:R06TripId)&limit=2" -OperatorKey $OperatorKey -Body $null)
  if ($receiptRows.Count -ne 0) { throw 'receipt_conflict' }
  $availabilityRows = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/driver_availability?select=driver_id,state,vehicle_id,reserved_booking_request_id,active_trip_id,version&driver_id=eq.$($Driver.Id)&limit=2" -OperatorKey $OperatorKey -Body $null)
  $vehicleRows = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/vehicles?select=id,driver_id,is_active,vehicle_type_code&id=eq.$($script:R06VehicleId)&limit=2" -OperatorKey $OperatorKey -Body $null)
  if ($availabilityRows.Count -ne 1 -or $vehicleRows.Count -ne 1 -or
      $availabilityRows[0].state -cne 'onTrip' -or $availabilityRows[0].active_trip_id -cne $script:R06TripId -or
      $availabilityRows[0].vehicle_id -cne $script:R06VehicleId -or
      [int]$availabilityRows[0].version -lt 1 -or
      $vehicleRows[0].driver_id -cne $Driver.Id -or $vehicleRows[0].is_active -ne $true -or
      $vehicleRows[0].vehicle_type_code -cne 'economy') { throw 'driver_preflight_mismatch' }
  return @{ Trip = $trip; Payment = $payment; Attempt = $attempt; Availability = $availabilityRows[0]; Vehicle = $vehicleRows[0] }
}

function Invoke-R06Retirement {
  param([scriptblock]$HttpTransport = $null)
  if ($HttpTransport) { $script:R06HttpTransport = $HttpTransport }
  $config = $null; $rider = $null; $driver = $null
  $riderPassword = $null; $driverPassword = $null; $operatorKey = $null
  try {
    $config = Get-R06Configuration
    $riderPassword = Read-Host 'Password for approved R06 Rider' -AsSecureString
    $driverPassword = Read-Host 'Password for approved R06 Driver' -AsSecureString
    $operatorKey = Read-Host 'Service-role key for read-only R06 preflight' -AsSecureString
    Assert-R06OperatorKey -OperatorKey $operatorKey
    $rider = Get-R06Actor -Kind rider -Email $script:R06RiderEmail -Password $riderPassword -AnonKey $config.Key
    $riderPassword = $null
    $driver = Get-R06Actor -Kind driver -Email $script:R06DriverEmail -Password $driverPassword -AnonKey $config.Key
    $driverPassword = $null
    Write-Output 'R06 authentication: Rider verified; Driver verified.'
    $preflight = Get-R06Preflight -Rider $rider -Driver $driver -AnonKey $config.Key -OperatorKey $operatorKey
    Write-Output 'R06 read-only preflight passed.'

    # Each mutation is issued once. Transport failures are ambiguous and halt.
    Assert-R06ActorSession -Actor $rider -AnonKey $config.Key
    $cancelled = Invoke-R06Rpc -Name 'rider_retire_r06_card_fixture' -Token $rider.Token -AnonKey $config.Key -Body @{
      target_trip_id = $script:R06TripId
      expected_trip_version = [int]$preflight.Trip.version
      target_payment_id = $preflight.Payment.id
      expected_payment_version = [int]$preflight.Payment.version
      target_attempt_id = $preflight.Attempt.id
    }
    if ($cancelled.trip_id -cne $script:R06TripId -or $cancelled.trip_status -cne 'cancelledByRider' -or
        $cancelled.payment_id -cne $preflight.Payment.id -or $cancelled.payment_status -cne 'paymentCancelled' -or
        $cancelled.attempt_id -cne $preflight.Attempt.id -or $cancelled.attempt_status -cne 'pending' -or
        [int]$cancelled.receipt_count -ne 0) { throw 'cancellation_result_unverified_stop' }

    $tripAfter = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/trips?select=id,rider_id,driver_id,status,version,payment_method&id=eq.$($script:R06TripId)&limit=2" -OperatorKey $operatorKey -Body $null)
    $paymentAfter = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/payments?select=id,trip_id,rider_id,method,authorized_amount_fils,final_amount_fils,card_status,version,authorized_at,paid_at,cancelled_at,refunded_at&id=eq.$($preflight.Payment.id)&limit=2" -OperatorKey $operatorKey -Body $null)
    $attemptAfter = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/payment_attempts?select=id,payment_id,type,status,authorization_cycle,attempt_sequence,provider_name,idempotency_key,requested_amount_fils,currency,provider_transaction_reference,sanitized_failure_code,sanitized_failure_message,completed_at,verified_at,refund_id,created_at&id=eq.$($preflight.Attempt.id)&payment_id=eq.$($preflight.Payment.id)&limit=2" -OperatorKey $operatorKey -Body $null)
    $attemptAfter = Get-R06Rows $attemptAfter
    if ($tripAfter.Count -ne 1 -or $tripAfter[0].status -cne 'cancelledByRider' -or
        $paymentAfter.Count -ne 1 -or $paymentAfter[0].card_status -cne 'paymentCancelled' -or
        $paymentAfter[0].method -cne 'card' -or
        $paymentAfter[0].authorized_amount_fils -ne $preflight.Payment.authorized_amount_fils -or
        $paymentAfter[0].final_amount_fils -ne $preflight.Payment.final_amount_fils -or
        $null -ne $paymentAfter[0].authorized_at -or $null -ne $paymentAfter[0].paid_at -or
        $null -eq $paymentAfter[0].cancelled_at -or $null -ne $paymentAfter[0].refunded_at -or
        $paymentAfter[0].version -le $preflight.Payment.version -or $attemptAfter.Count -ne 1 -or
        $attemptAfter[0].id -cne $preflight.Attempt.id -or $attemptAfter[0].status -cne 'pending' -or
        $attemptAfter[0].type -cne $preflight.Attempt.type -or
        $attemptAfter[0].authorization_cycle -ne $preflight.Attempt.authorization_cycle -or
        $attemptAfter[0].attempt_sequence -ne $preflight.Attempt.attempt_sequence -or
        $attemptAfter[0].provider_name -cne $preflight.Attempt.provider_name -or
        $attemptAfter[0].idempotency_key -cne $preflight.Attempt.idempotency_key -or
        $attemptAfter[0].requested_amount_fils -ne $preflight.Attempt.requested_amount_fils -or
        $attemptAfter[0].currency -cne $preflight.Attempt.currency -or
        $attemptAfter[0].sanitized_failure_code -cne $preflight.Attempt.sanitized_failure_code -or
        $attemptAfter[0].sanitized_failure_message -cne $preflight.Attempt.sanitized_failure_message -or
        $attemptAfter[0].refund_id -cne $preflight.Attempt.refund_id -or
        $attemptAfter[0].created_at -cne $preflight.Attempt.created_at -or
        $null -ne $attemptAfter[0].provider_transaction_reference -or
        $null -ne $attemptAfter[0].completed_at -or $null -ne $attemptAfter[0].verified_at) {
      throw 'cancellation_reconciliation_failed_stop'
    }
    $reservationAfter = Invoke-R06OperatorRead -Path '/rest/v1/rpc/backend_read_stripe_test_preparation' -OperatorKey $operatorKey -Body @{ target_attempt_id = $preflight.Attempt.id; actor_rider_id = $rider.Id }
  Assert-R06ReservationAbsent -Reservation $reservationAfter -ConflictCode 'reservation_reconciliation_failed_stop'
    $receiptAfter = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/receipts?select=id&trip_id=eq.$($script:R06TripId)&limit=2" -OperatorKey $operatorKey -Body $null)
    if ($receiptAfter.Count -ne 0) { throw 'receipt_reconciliation_failed_stop' }
    $availabilityNow = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/driver_availability?select=driver_id,state,vehicle_id,reserved_booking_request_id,active_trip_id,version&driver_id=eq.$($driver.Id)&limit=2" -OperatorKey $operatorKey -Body $null)
    if ($availabilityNow.Count -ne 1 -or $availabilityNow[0].state -cne 'offline' -or
        $null -ne $availabilityNow[0].active_trip_id -or $null -ne $availabilityNow[0].reserved_booking_request_id) {
      throw 'driver_post_cancellation_reconciliation_failed_stop'
    }
    Assert-R06ActorSession -Actor $driver -AnonKey $config.Key
    $available = Invoke-R06Rpc -Name 'driver_set_availability' -Token $driver.Token -AnonKey $config.Key -Body @{
      requested_state = 'available'
      requested_vehicle_id = $script:R06VehicleId
      expected_version = [int]$availabilityNow[0].version
    }
    if ($available.driver_id -cne $driver.Id -or $available.state -cne 'available' -or $available.vehicle_id -cne $script:R06VehicleId) {
      throw 'availability_result_unverified_stop'
    }
    $finalTrip = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/trips?select=id,status,version&id=eq.$($script:R06TripId)&limit=2" -OperatorKey $operatorKey -Body $null)
    $finalPayment = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/payments?select=id,trip_id,method,authorized_amount_fils,final_amount_fils,card_status,version,authorized_at,paid_at,cancelled_at,refunded_at&id=eq.$($preflight.Payment.id)&limit=2" -OperatorKey $operatorKey -Body $null)
    $finalAttempts = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/payment_attempts?select=id,payment_id,type,status,authorization_cycle,attempt_sequence,provider_name,idempotency_key,requested_amount_fils,currency,provider_transaction_reference,sanitized_failure_code,sanitized_failure_message,completed_at,verified_at,refund_id,created_at&id=eq.$($preflight.Attempt.id)&payment_id=eq.$($preflight.Payment.id)&limit=2" -OperatorKey $operatorKey -Body $null)
    $finalAvailability = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/driver_availability?select=driver_id,state,vehicle_id,reserved_booking_request_id,active_trip_id,version&driver_id=eq.$($driver.Id)&limit=2" -OperatorKey $operatorKey -Body $null)
    $finalVehicles = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/vehicles?select=id,driver_id,is_active,vehicle_type_code&id=eq.$($script:R06VehicleId)&limit=2" -OperatorKey $operatorKey -Body $null)
    $finalActiveTrips = Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/trips?select=id,driver_id,status&driver_id=eq.$($driver.Id)&status=in.(accepted,driverArriving,driverArrived,inProgress)&limit=3" -OperatorKey $operatorKey -Body $null)
    $finalReservation = Invoke-R06OperatorRead -Path '/rest/v1/rpc/backend_read_stripe_test_preparation' -OperatorKey $operatorKey -Body @{ target_attempt_id = $preflight.Attempt.id; actor_rider_id = $rider.Id }
    Assert-R06ReservationAbsent -Reservation $finalReservation -ConflictCode 'final_reconciliation_failed_stop'
    $finalReceiptCount = (Get-R06Rows (Invoke-R06OperatorRead -Path "/rest/v1/receipts?select=id&trip_id=eq.$($script:R06TripId)&limit=2" -OperatorKey $operatorKey -Body $null)).Count
    if ($finalTrip.Count -ne 1 -or $finalTrip[0].status -cne 'cancelledByRider' -or
        $finalPayment.Count -ne 1 -or $finalPayment[0].card_status -cne 'paymentCancelled' -or
        $finalPayment[0].method -cne 'card' -or
        $finalPayment[0].authorized_amount_fils -ne $preflight.Payment.authorized_amount_fils -or
        $finalPayment[0].final_amount_fils -ne $preflight.Payment.final_amount_fils -or
        $null -ne $finalPayment[0].authorized_at -or $null -ne $finalPayment[0].paid_at -or
        $null -eq $finalPayment[0].cancelled_at -or $null -ne $finalPayment[0].refunded_at -or
        $finalAttempts.Count -ne 1 -or $finalAttempts[0].id -cne $preflight.Attempt.id -or
        $finalAttempts[0].status -cne 'pending' -or $finalAttempts[0].created_at -cne $preflight.Attempt.created_at -or
        $finalAttempts[0].type -cne $preflight.Attempt.type -or
        $finalAttempts[0].authorization_cycle -ne $preflight.Attempt.authorization_cycle -or
        $finalAttempts[0].attempt_sequence -ne $preflight.Attempt.attempt_sequence -or
        $finalAttempts[0].provider_name -cne $preflight.Attempt.provider_name -or
        $finalAttempts[0].idempotency_key -cne $preflight.Attempt.idempotency_key -or
        $finalAttempts[0].requested_amount_fils -ne $preflight.Attempt.requested_amount_fils -or
        $finalAttempts[0].currency -cne $preflight.Attempt.currency -or
        $finalAttempts[0].sanitized_failure_code -cne $preflight.Attempt.sanitized_failure_code -or
        $finalAttempts[0].sanitized_failure_message -cne $preflight.Attempt.sanitized_failure_message -or
        $finalAttempts[0].refund_id -cne $preflight.Attempt.refund_id -or
        $null -ne $finalAttempts[0].provider_transaction_reference -or
        $null -ne $finalAttempts[0].completed_at -or $null -ne $finalAttempts[0].verified_at -or
        $finalAvailability.Count -ne 1 -or $finalAvailability[0].state -cne 'available' -or
        $finalAvailability[0].vehicle_id -cne $script:R06VehicleId -or
        $null -ne $finalAvailability[0].active_trip_id -or $null -ne $finalAvailability[0].reserved_booking_request_id -or
        $finalVehicles.Count -ne 1 -or $finalVehicles[0].is_active -ne $true -or
        $finalActiveTrips.Count -ne 0 -or $finalReservation -ne $null -or $finalReceiptCount -ne 0) {
      throw 'final_reconciliation_failed_stop'
    }
    Write-Output 'R06 retirement complete: Trip cancelled; Payment cancelled; Attempt preserved pending; Reservation count zero; Receipt count zero; Driver available.'
  } finally {
    if ($riderPassword) { $riderPassword.Dispose() }
    if ($driverPassword) { $driverPassword.Dispose() }
    if ($rider) { $rider.Token = $null }
    if ($driver) { $driver.Token = $null }
    if ($config) { $config.Key = $null }
    if ($operatorKey) { $operatorKey.Dispose() }
    $script:R06HttpTransport = $null
    [GC]::Collect()
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  try { Invoke-R06Retirement }
  catch {
    $safeCode = [string]$_.Exception.Data['R06Code']
    if (-not $safeCode) { $safeCode = $_.Exception.Message }
    if ($safeCode -notmatch '^[a-z0-9_]+$') { $safeCode = 'operator_stopped_safely' }
    Write-Output "R06 operator stopped safely: $safeCode"
    exit 2
  }
}
