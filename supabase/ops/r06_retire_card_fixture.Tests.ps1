$operatorPath = Join-Path $PSScriptRoot 'r06_retire_card_fixture.ps1'
. $operatorPath

function New-TestJwt {
  param(
    [string]$Subject,
    [long]$ExpiresAt,
    [string]$Role = 'authenticated',
    [string]$Issuer = 'https://ykasivejjchupswqyxpm.supabase.co/auth/v1',
    [string]$ProjectRef
  )
  $payloadObject = @{ sub = $Subject; iss = $Issuer; exp = $ExpiresAt; role = $Role }
  if ($PSBoundParameters.ContainsKey('ProjectRef')) { $payloadObject.ref = $ProjectRef }
  $payload = $payloadObject | ConvertTo-Json -Compress
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload)).TrimEnd('=').Replace('+','-').Replace('/','_')
  return "e30.$encoded.signature"
}

function New-TestJwtFromClaims {
  param([Parameter(Mandatory)][hashtable]$Claims)
  $payload = $Claims | ConvertTo-Json -Compress
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload)).TrimEnd('=').Replace('+','-').Replace('/','_')
  return "e30.$encoded.signature"
}

function New-TestOperatorJwt {
  param([hashtable]$Overrides = @{})
  $claims = @{
    iss = 'supabase'
    ref = 'ykasivejjchupswqyxpm'
    role = 'service_role'
    exp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3000
  }
  foreach ($name in $Overrides.Keys) { $claims[$name] = $Overrides[$name] }
  return New-TestJwtFromClaims -Claims $claims
}

function Project-R06TestRows {
  param([string]$Uri, [object[]]$Rows)
  $select = [regex]::Match($Uri, '(?:\?|&)select=([^&]+)')
  if (-not $select.Success) { return ,@($Rows) }
  $fields = [Uri]::UnescapeDataString($select.Groups[1].Value).Split(',')
  $projected = @(
    foreach ($row in $Rows) {
      $item = [ordered]@{}
      foreach ($field in $fields) {
        if ($row.ContainsKey($field)) { $item[$field] = $row[$field] }
      }
      [pscustomobject]$item
    }
  )
  return ,$projected
}

function New-R06TestTransport {
  return {
    param($Method, $Uri, $Headers, $Body)
    $payload = $null
    $authorization = if ($Headers.ContainsKey('Authorization')) { [string]$Headers['Authorization'] } else { '' }
    if ($authorization -match '^Bearer (.+)$') {
      try { $payload = Get-R06JwtPayload $Matches[1] } catch { }
    }
    $role = ''; $subject = ''
    if ($payload) {
      $role = [string]$payload.role
      if ($payload.PSObject.Properties['sub']) { $subject = [string]$payload.sub }
    }
    $global:r06TestRequests.Add([pscustomobject]@{
      Method = $Method; Uri = $Uri; Role = $role; Subject = $subject
      ApiKeyPresent = -not [string]::IsNullOrWhiteSpace([string]$Headers['apikey'])
      LegacyBearerMatchesApiKey = ($role -eq 'service_role' -and $Headers['apikey'] -ceq $Matches[1])
    })
    if ($role -eq 'service_role' -and $global:r06Scenario -eq 'bad_operator_auth') {
      throw 'simulated_401_invalid_signature'
    }
    if ($Uri -like '*/auth/v1/token*') {
      $email = [string]$Body.email
      $id = if ($email -eq 'yousufrider@gmail.com') { $global:r06TestRiderId } else { $global:r06TestDriverId }
      $expiry = if ($global:r06Scenario -eq 'expired') { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 10 } else { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3000 }
      return @{ access_token = (New-TestJwt -Subject $id -ExpiresAt $expiry); refresh_token = 'test-refresh-token'; user = @{ id = $id; email = $email } }
    }
    if ($Uri -like '*/auth/v1/user') {
      $id = [string]$payload.sub
      $email = if ($id -eq $global:r06TestRiderId) { 'yousufrider@gmail.com' } else { 'yousufdriver@gmail.com' }
      return @{ id = $id; email = $email }
    }
    if ($Uri -like '*/rest/v1/users?*') {
      $id = if ($Uri -like "*id=eq.$($global:r06TestRiderId)*") { $global:r06TestRiderId } else { $global:r06TestDriverId }
      $email = if ($id -eq $global:r06TestRiderId) { 'yousufrider@gmail.com' } else { 'yousufdriver@gmail.com' }
      $role = if ($id -eq $global:r06TestRiderId) { 'rider' } else { 'driver' }
      return ,(Project-R06TestRows -Uri $Uri -Rows @(@{ id = $id; email = $email; role = $role; is_blocked = $false }))
    }
    if ($Uri -like '*/rest/v1/driver_profiles?*') { return ,(Project-R06TestRows -Uri $Uri -Rows @(@{ user_id = $global:r06TestDriverId; approval_status = 'approved' })) }
    if ($Uri -like '*/rest/v1/trips?*') {
      if ($Uri -match 'status=in\.\(accepted,driverArriving,driverArrived,inProgress\)') {
        if ($global:r06Stage -eq 'cancelled' -or $global:r06Stage -eq 'available') { return ,@() }
      }
      $status = if ($global:r06Stage -eq 'cancelled' -or $global:r06Stage -eq 'available') { 'cancelledByRider' } else { 'accepted' }
      return ,(Project-R06TestRows -Uri $Uri -Rows @(@{ id = 'ceff7eb6-2d1f-4744-9cbc-243d80d550ba'; booking_request_id = '33333333-3333-4333-8333-333333333333'; rider_id = $global:r06TestRiderId; driver_id = $global:r06TestDriverId; vehicle_id = '48d007ab-c13c-4ff8-93f3-1dc7f1e6975d'; payment_method = 'card'; status = $status; version = $(if ($status -eq 'accepted') { 1 } else { 2 }); currency = 'JOD'; original_fare_fils = 2150; current_fare_fils = 2150 }))
    }
    if ($Uri -like '*/rest/v1/payments?*') {
      $status = if (($global:r06Stage -eq 'cancelled' -or $global:r06Stage -eq 'available') -and $global:r06Scenario -ne 'bad_reconciliation') { 'paymentCancelled' } else { 'cardPaymentPending' }
      return ,(Project-R06TestRows -Uri $Uri -Rows @(@{ id = '44444444-4444-4444-8444-444444444444'; trip_id = 'ceff7eb6-2d1f-4744-9cbc-243d80d550ba'; rider_id = $global:r06TestRiderId; method = 'card'; final_amount_fils = 2150; authorized_amount_fils = 2150; currency = 'JOD'; card_status = $status; version = $(if ($status -eq 'cardPaymentPending') { 1 } else { 2 }); authorized_at = $null; paid_at = $null; cancelled_at = $(if ($status -eq 'cardPaymentPending') { $null } else { '2026-10-27T00:00:00Z' }); refunded_at = $null }))
    }
    if ($Uri -like '*/rest/v1/payment_attempts?*') {
      $reference = if ($global:r06Scenario -eq 'provider_reference') { 'pi_test_reference' } else { $null }
      return ,(Project-R06TestRows -Uri $Uri -Rows @(@{ id = '55555555-5555-4555-8555-555555555555'; payment_id = '44444444-4444-4444-8444-444444444444'; type = 'initialAuthorization'; status = 'pending'; authorization_cycle = 1; attempt_sequence = 1; provider_name = 'stripe'; idempotency_key = 'r06-test-operation'; requested_amount_fils = 2150; currency = 'JOD'; provider_transaction_reference = $reference; completed_at = $null; verified_at = $null; sanitized_failure_code = $null; sanitized_failure_message = $null; refund_id = $null; created_at = $global:r06AttemptCreatedAt }))
    }
    if ($Uri -like '*/rest/v1/receipts?*') { return ,@() }
    if ($Uri -like '*/rest/v1/driver_availability?*') {
      $state = if ($global:r06Stage -eq 'available') { 'available' } elseif ($global:r06Stage -eq 'cancelled') { 'offline' } else { 'onTrip' }
      $activeTrip = if ($state -eq 'onTrip') { 'ceff7eb6-2d1f-4744-9cbc-243d80d550ba' } else { $null }
      $vehicle = if ($state -eq 'available' -or $state -eq 'onTrip') { '48d007ab-c13c-4ff8-93f3-1dc7f1e6975d' } else { $null }
      return ,(Project-R06TestRows -Uri $Uri -Rows @(@{ driver_id = $global:r06TestDriverId; state = $state; vehicle_id = $vehicle; reserved_booking_request_id = $null; active_trip_id = $activeTrip; version = $(if ($state -eq 'onTrip') { 1 } else { 2 }) }))
    }
    if ($Uri -like '*/rest/v1/vehicles?*') { return ,(Project-R06TestRows -Uri $Uri -Rows @(@{ id = '48d007ab-c13c-4ff8-93f3-1dc7f1e6975d'; driver_id = $global:r06TestDriverId; is_active = $true; vehicle_type_code = 'economy' })) }
    if ($Uri -like '*/rpc/backend_read_stripe_test_preparation') {
      if ($global:r06Scenario -eq 'reservation') { return @{ disposition = 'existing'; state = 'unknown'; reference = $null } }
      return $null
    }
    if ($Uri -like '*/rpc/rider_retire_r06_card_fixture') {
      $global:r06MutationCalls++
      if ($global:r06Scenario -eq 'stale_trip' -or $global:r06Scenario -eq 'stale_payment') { throw 'simulated_40001_version_conflict' }
      if ($global:r06Scenario -eq 'unknown') { throw 'simulated_timeout_unknown_outcome' }
      if ($global:r06Scenario -eq 'ambiguous') { return @{ trip_id = 'unexpected-trip'; trip_status = 'cancelledByRider' } }
      $global:r06Stage = 'cancelled'
      return @{ trip_id = 'ceff7eb6-2d1f-4744-9cbc-243d80d550ba'; trip_status = 'cancelledByRider'; trip_version = 2; payment_id = '44444444-4444-4444-8444-444444444444'; payment_status = 'paymentCancelled'; payment_version = 2; attempt_id = '55555555-5555-4555-8555-555555555555'; attempt_status = 'pending'; receipt_count = 0 }
    }
    if ($Uri -like '*/rpc/driver_set_availability') {
      $global:r06MutationCalls++
      $global:r06Stage = 'available'
      return @{ driver_id = $global:r06TestDriverId; state = 'available'; vehicle_id = '48d007ab-c13c-4ff8-93f3-1dc7f1e6975d' }
    }
    throw 'unexpected_mock_request'
  }
}

Describe 'R06 local retirement operator' {
  BeforeEach {
    $global:r06TestRiderId = '11111111-1111-4111-8111-111111111111'
    $global:r06TestDriverId = '22222222-2222-4222-8222-222222222222'
    $global:r06TestRequests = [System.Collections.Generic.List[object]]::new()
    $global:r06MutationCalls = 0
    $global:r06Scenario = 'valid'
    $global:r06Stage = 'preflight'
    $global:r06ReadCount = 0
    $global:r06AttemptCreatedAt = [DateTimeOffset]::UtcNow.AddMinutes(-10).ToString('o')
    $global:r06OperatorJwt = $null
    Mock Get-R06Configuration { return @{ Url = $script:R06ProjectUrl; Key = 'test-publishable-key' } }
    Mock Read-Host {
      $global:r06ReadCount++
      if ($global:r06ReadCount -eq 3) {
        $operatorJwt = if ($global:r06OperatorJwt) { $global:r06OperatorJwt } else { New-TestOperatorJwt }
        return ConvertTo-SecureString $operatorJwt -AsPlainText -Force
      }
      return ConvertTo-SecureString 'test-only-password-do-not-print' -AsPlainText -Force
    }
  }

  It 'reconciles exact selected Payment fields before authorized Driver restoration' {
    $global:r06OperatorJwt = New-TestOperatorJwt -Overrides @{ signature_marker = 'test-only-operator-secret-marker' }
    $output = Invoke-R06Retirement -HttpTransport (New-R06TestTransport) | Out-String
    $output | Should Match 'R06 retirement complete'
    $output | Should Not Match 'test-only-password-do-not-print|test-refresh-token|test-only-operator-secret-marker'
    $global:r06MutationCalls | Should Be 2
    $retire = @($global:r06TestRequests | Where-Object { $_.Uri -like '*/rpc/rider_retire_r06_card_fixture' })
    $availability = @($global:r06TestRequests | Where-Object { $_.Uri -like '*/rpc/driver_set_availability' })
    $retire.Count | Should Be 1
    $retire[0].Role | Should Be 'authenticated'
    $retire[0].Subject | Should Be $global:r06TestRiderId
    $availability.Count | Should Be 1
    $availability[0].Role | Should Be 'authenticated'
    $availability[0].Subject | Should Be $global:r06TestDriverId
    $operatorReads = @($global:r06TestRequests | Where-Object { $_.Role -eq 'service_role' })
    $operatorReads.Count | Should BeGreaterThan 0
    @($operatorReads | Where-Object {
      -not $_.ApiKeyPresent -or -not $_.LegacyBearerMatchesApiKey -or
      ($_.Method -ne 'GET' -and $_.Uri -notlike '*/rpc/backend_read_stripe_test_preparation')
    }).Count | Should Be 0
    @($operatorReads | Where-Object { $_.Uri -notmatch '^https://ykasivejjchupswqyxpm\.supabase\.co/rest/v1/(trips|payments|payment_attempts|receipts|driver_availability|vehicles)\?' -and $_.Uri -notlike '*/rpc/backend_read_stripe_test_preparation' }).Count | Should Be 0
    $global:r06TestRequests.IndexOf($operatorReads[0]) | Should BeLessThan $global:r06TestRequests.IndexOf($retire[0])
    $global:r06TestRequests.IndexOf($availability[0]) | Should BeGreaterThan $global:r06TestRequests.IndexOf($retire[0])
    $paymentAfter = @($global:r06TestRequests | Where-Object {
      $_.Uri -like '*/rest/v1/payments?select=*&id=eq.*'
    } | Select-Object -First 1)
    $paymentAfter.Count | Should Be 1
    $selectedPaymentFields = $paymentAfter[0].Uri.Split('?')[1].Split('&')[0].Split('=')[1].Split(',')
    ($selectedPaymentFields -contains 'authorized_amount_fils') | Should Be $true
  }

  It 'rejects expired actor sessions before protected reads or mutations' {
    $global:r06Scenario = 'expired'
    $output = ''
    try { $output = Invoke-R06Retirement -HttpTransport (New-R06TestTransport) | Out-String } catch { $output += $_.Exception.Message }
    $output | Should Not Match 'test-only-password-do-not-print|test-refresh-token|signature'
    @($global:r06TestRequests | Where-Object { $_.Uri -like '*/rest/v1/*' -or $_.Uri -like '*/rpc/*' }).Count | Should Be 0
  }

  It 'stops without mutation when a reservation exists' {
    $global:r06Scenario = 'reservation'
    { Invoke-R06Retirement -HttpTransport (New-R06TestTransport) } | Should Throw
    $global:r06MutationCalls | Should Be 0
  }

  It 'stops without mutation when a provider reference exists' {
    $global:r06Scenario = 'provider_reference'
    { Invoke-R06Retirement -HttpTransport (New-R06TestTransport) } | Should Throw
    $global:r06MutationCalls | Should Be 0
  }

  It 'does not retry stale Trip or Payment versions' {
    foreach ($scenario in @('stale_trip','stale_payment')) {
      $global:r06Scenario = $scenario
      $global:r06Stage = 'preflight'
      $global:r06MutationCalls = 0
      $global:r06ReadCount = 0
      { Invoke-R06Retirement -HttpTransport (New-R06TestTransport) } | Should Throw
      $global:r06MutationCalls | Should Be 1
      @($global:r06TestRequests | Where-Object { $_.Uri -like '*/rpc/driver_set_availability' }).Count | Should Be 0
      $global:r06TestRequests.Clear()
    }
  }

  It 'does not retry an uncertain mutation outcome or restore Driver availability' {
    $global:r06Scenario = 'unknown'
    { Invoke-R06Retirement -HttpTransport (New-R06TestTransport) } | Should Throw
    @($global:r06TestRequests | Where-Object { $_.Uri -like '*/rpc/rider_retire_r06_card_fixture' }).Count | Should Be 1
    @($global:r06TestRequests | Where-Object { $_.Uri -like '*/rpc/driver_set_availability' }).Count | Should Be 0
  }

  It 'does not restore Driver availability after an ambiguous cancellation response' {
    $global:r06Scenario = 'ambiguous'
    { Invoke-R06Retirement -HttpTransport (New-R06TestTransport) } | Should Throw
    @($global:r06TestRequests | Where-Object { $_.Uri -like '*/rpc/rider_retire_r06_card_fixture' }).Count | Should Be 1
    @($global:r06TestRequests | Where-Object { $_.Uri -like '*/rpc/driver_set_availability' }).Count | Should Be 0
  }

  It 'does not restore Driver availability when cancellation reconciliation fails' {
    $global:r06Scenario = 'bad_reconciliation'
    { Invoke-R06Retirement -HttpTransport (New-R06TestTransport) } | Should Throw
    @($global:r06TestRequests | Where-Object { $_.Uri -like '*/rpc/rider_retire_r06_card_fixture' }).Count | Should Be 1
    @($global:r06TestRequests | Where-Object { $_.Uri -like '*/rpc/driver_set_availability' }).Count | Should Be 0
  }

  It 'refuses non-read-only privileged paths before making a request' {
    $key = ConvertTo-SecureString (New-TestOperatorJwt) -AsPlainText -Force
    { Invoke-R06OperatorRead -Path '/rest/v1/rpc/rider_retire_r06_card_fixture' -OperatorKey $key -Body @{} } | Should Throw
    $global:r06TestRequests.Count | Should Be 0
    $key.Dispose()
  }

  It 'accepts documented legacy service-role claims for the exact project' {
    $key = ConvertTo-SecureString (New-TestOperatorJwt) -AsPlainText -Force
    { Assert-R06OperatorKey -OperatorKey $key } | Should Not Throw
    $key.Dispose()
  }

  It 'rejects wrong project, issuer, role, and expired legacy service-role claims' {
    $invalidClaims = @(
      @{ ref = 'another-project-reference' },
      @{ iss = 'https://ykasivejjchupswqyxpm.supabase.co/auth/v1' },
      @{ role = 'anon' },
      @{ exp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 1 }
    )
    foreach ($override in $invalidClaims) {
      $key = ConvertTo-SecureString (New-TestOperatorJwt -Overrides $override) -AsPlainText -Force
      { Assert-R06OperatorKey -OperatorKey $key } | Should Throw 'operator_credential_invalid'
      $key.Dispose()
    }
  }

  It 'rejects missing, malformed, and opaque secret-key claims without leaking input' {
    $invalidTokens = @(
      (New-TestJwtFromClaims -Claims @{ iss = 'supabase'; role = 'service_role'; exp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3000 }),
      (New-TestJwtFromClaims -Claims @{ iss = 'supabase'; ref = 'ykasivejjchupswqyxpm'; role = 'service_role'; exp = 'not-a-number' }),
      'sb_secret_test_only_opaque_key'
    )
    foreach ($token in $invalidTokens) {
      $key = ConvertTo-SecureString $token -AsPlainText -Force
      $errorMessage = ''
      try { Assert-R06OperatorKey -OperatorKey $key } catch { $errorMessage = $_.Exception.Message }
      $errorMessage | Should Be 'operator_credential_invalid'
      $errorMessage | Should Not Match ([regex]::Escape($token))
      $key.Dispose()
    }
  }

  It 'makes no authentication or mutation request after rejecting operator credentials' {
    $global:r06OperatorJwt = New-TestOperatorJwt -Overrides @{
      ref = 'wrong-project-reference'
      signature_marker = 'test-only-secret-marker'
    }
    $errorMessage = ''
    try { Invoke-R06Retirement -HttpTransport (New-R06TestTransport) | Out-Null }
    catch { $errorMessage = $_.Exception.Message }
    $errorMessage | Should Be 'operator_credential_invalid'
    $errorMessage | Should Not Match 'test-only-secret-marker|test-only-password-do-not-print'
    $global:r06TestRequests.Count | Should Be 0
    $global:r06MutationCalls | Should Be 0
  }

  It 'halts without mutation when Supabase rejects the operator JWT on the read-only preflight' {
    $global:r06Scenario = 'bad_operator_auth'
    $errorMessage = ''
    try { Invoke-R06Retirement -HttpTransport (New-R06TestTransport) | Out-Null }
    catch { $errorMessage = $_.Exception.Message }
    $errorMessage | Should Be 'r06_request_failed'
    $operatorReads = @($global:r06TestRequests | Where-Object { $_.Role -eq 'service_role' })
    $operatorReads.Count | Should Be 1
    $operatorReads[0].Method | Should Be 'GET'
    $operatorReads[0].Uri | Should Match '/rest/v1/trips\?'
    @($global:r06TestRequests | Where-Object { $_.Uri -like '*/rpc/rider_retire_r06_card_fixture' -or $_.Uri -like '*/rpc/driver_set_availability' }).Count | Should Be 0
    $global:r06MutationCalls | Should Be 0
  }
}
