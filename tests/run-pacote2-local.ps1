param([ValidateSet('Node','Browser')][string]$Mode='Node', [string]$LogRoot=(Join-Path $env:TEMP 'primeline-fecho-local-final'))
$ErrorActionPreference='Stop'
$node='C:\Users\conta\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
$env:QUADRO_PG_BIN=Join-Path $env:TEMP 'primeline-doc-guard-pg176\package\native\bin'
$env:QUADRO_TEST_DEPS=Join-Path $env:TEMP 'primeline-medicina-test-deps\runtime\node_modules'
$env:QUADRO_PGLITE=Join-Path $PSScriptRoot 'runtime\node_modules\@electric-sql\pglite\dist\index.js'
$env:QUADRO_POSTGREST=Join-Path $env:TEMP 'primeline-authorization-postgrest\postgrest.exe'
$env:MEDICINA_PG_BIN=$env:QUADRO_PG_BIN
$env:MEDICINA_TEST_DEPS=$env:QUADRO_TEST_DEPS
$env:VIATURAS_PG_BIN=$env:QUADRO_PG_BIN
$env:VIATURAS_PG_MODULE=Join-Path $env:QUADRO_TEST_DEPS 'pg'
$env:LOCAL_PG_BIN=$env:QUADRO_PG_BIN
$env:LOCAL_PG_DEPS=$env:QUADRO_TEST_DEPS
# PostgREST has no bundled libpq: use the already installed client's complete DLL set.
$postgrestDllBin=if($env:QUADRO_POSTGREST_DLL_BIN){$env:QUADRO_POSTGREST_DLL_BIN}else{'C:\Program Files\PostgreSQL\17\bin'}
$env:PATH=$env:QUADRO_PG_BIN+';'+$env:PATH
if(Test-Path (Join-Path $postgrestDllBin 'libpq.dll')){$env:PATH=$postgrestDllBin+';'+$env:PATH}
$env:RH_TEST_DEPS=Join-Path $PSScriptRoot 'runtime'
$env:LOGIN_TEST_DEPS=Join-Path $PSScriptRoot 'runtime\package.json'
$env:PLANNING_PLAYWRIGHT='C:\Users\conta\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\node_modules\playwright'
New-Item -ItemType Directory -Force $LogRoot | Out-Null
Push-Location (Split-Path $PSScriptRoot)
try {
 $pattern=if($Mode -eq 'Node'){'*.test.mjs'}else{'*browser*.mjs'}
 $files=@(rg --files tests -g $pattern | Sort-Object -Unique)
 $files | ConvertTo-Json | Set-Content (Join-Path $LogRoot ($Mode+'-discovery.json'))
 if($Mode -eq 'Node') {
  & $node --test --test-concurrency=1 --test-reporter=spec @files *> (Join-Path $LogRoot 'Node.log')
  $code=$LASTEXITCODE
  Get-Content (Join-Path $LogRoot 'Node.log') -Tail 12
  exit $code
 }
 $results=@()
 foreach($file in $files){
  & $node $file *> (Join-Path $LogRoot ((Split-Path $file -Leaf)+'.log'))
  $results+=@{file=$file;exit=$LASTEXITCODE}
  Write-Output ($file+': '+$LASTEXITCODE)
 }
 $results | ConvertTo-Json | Set-Content (Join-Path $LogRoot 'Browser-results.json')
 if(@($results | Where-Object {$_.exit -ne 0}).Count){exit 1}
} finally {Pop-Location}
