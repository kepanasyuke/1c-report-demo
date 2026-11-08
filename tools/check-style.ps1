<#
.SYNOPSIS
	Проверка BSL-файлов на соответствие правилам оформления команды.

.DESCRIPTION
	Правила:
	  1. Один выход: в функции ровно один "Возврат" и он - последняя инструкция.
	  2. В процедурах "Возврат" запрещён.
	  3. Тело функции 1-2 инструкции (предупреждение после 2, ошибка после 4).
	  4. Запрещены "Прервать", "Продолжить", "Перейти", "Пока".
	  5. Отступ - табуляцией.
	  6. Запрещена команда "Сообщить(".
	Код возврата: 0 - нарушений нет, 1 - есть ошибки.

.EXAMPLE
	powershell -ExecutionPolicy Bypass -File tools\check-style.ps1
#>

param(
	[string]$Path = (Join-Path $PSScriptRoot '..\src')
)

$ErrorActionPreference = 'Stop'

$forbidden = @{
	'Прервать'   = 'выход из цикла запрещён, используйте условие'
	'Продолжить' = 'переход к следующей итерации запрещён'
	'Перейти'    = 'переход по метке запрещён'
	'Пока'       = 'цикл "Пока" запрещён, используйте "Для" / "Для Каждого"'
}

$maxWarn = 2
$maxError = 4
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Get-CodeLines {
	param([string[]]$Lines)

	$result = @()
	$inBlockComment = $false

	for ($i = 0; $i -lt $Lines.Count; $i++) {
		$text = $Lines[$i]
		$trimmed = $text.Trim()

		if ($inBlockComment) {
			if ($trimmed -match '^\*\/') { $inBlockComment = $false }
			continue
		}

		if ($trimmed -match '^\/\*') {
			if ($trimmed -notmatch '\*\/$') { $inBlockComment = $true }
			continue
		}

		if ($trimmed -eq '' -or $trimmed -match '^\/\/') { continue }

		$result += [pscustomobject]@{ Number = $i + 1; Text = $text }
	}

	return $result
}

function Test-File {
	param([string]$File)

	$name = Split-Path -Leaf $File
	$lines = Get-CodeLines -Lines (Get-Content -LiteralPath $File -Encoding UTF8)
	$routine = $null
	$body = @()

	foreach ($line in $lines) {

		if ($line.Text -match '^\s*(Функция|Процедура)\s+([A-Za-zА-Яа-яЁё0-9_]+)\s*\(') {
			$routine = [pscustomobject]@{
				Kind = $matches[1]
				Name = $matches[2]
				Line = $line.Number
			}
			$body = @()
			continue
		}

		if ($line.Text -match '^\s*Конец(Функции|Процедуры)') {
			if ($null -ne $routine) {
				Test-Routine -File $name -Routine $routine -Body $body
				$routine = $null
				$body = @()
			}
			continue
		}

		if ($null -ne $routine) { $body += $line }
	}

	foreach ($line in $lines) {
		foreach ($word in $forbidden.Keys) {
			if ($line.Text -match "(?<![\wА-Яа-яЁё])$word(?![\wА-Яа-яЁё])") {
				$errors.Add("${name}:$($line.Number) - $word : $($forbidden[$word])")
			}
		}

		if ($line.Text -match '(?<![\wА-Яа-яЁё])Сообщить\s*\(') {
			$errors.Add("${name}:$($line.Number) - Сообщить() : используйте СообщениеПользователю")
		}

		if ($line.Text -match '^ +[^\s]') {
			$warnings.Add("${name}:$($line.Number) - отступ пробелами, нужен символ табуляции")
		}
	}
}

function Test-Routine {
	param([string]$File, [pscustomobject]$Routine, [object[]]$Body)

	$label = "$File`:$($Routine.Line) - $($Routine.Name)"
	$returns = @($Body | Where-Object { $_.Text -match '(?<![\wА-Яа-яЁё])Возврат(?![\wА-Яа-яЁё])' })
	$isFunction = $Routine.Kind -eq 'Функция'

	if ($isFunction -and $returns.Count -eq 0) {
		$errors.Add("$label - функция без Возврат")
	}

	if ($isFunction -and $returns.Count -gt 1) {
		$errors.Add("$label - выходов $($returns.Count), нужен один")
	}

	if (-not $isFunction -and $returns.Count -gt 0) {
		$errors.Add("$label - Возврат в процедуре")
	}

	if ($returns.Count -eq 1 -and $Body.Count -gt 0 -and $Body[-1] -ne $returns[0]) {
		$errors.Add("$label - Возврат не последняя инструкция")
	}

	$statements = @($Body | Where-Object { $_.Text -notmatch '(?<![\wА-Яа-яЁё])Возврат(?![\wА-Яа-яЁё])' })
	$count = $statements.Count

	if ($count -gt $maxError) {
		$errors.Add("$label - инструкций $count, допустимо не более $maxError")
	}
	elseif ($count -gt $maxWarn) {
		$warnings.Add("$label - инструкций $count, целевой ориентир 1-$maxWarn")
	}
}

$files = @(Get-ChildItem -LiteralPath $Path -Filter '*.bsl' -Recurse -File)

if ($files.Count -eq 0) {
	Write-Host "Не найдено .bsl файлов в $Path"
	exit 0
}

foreach ($file in $files) {
	Test-File -File $file.FullName
}

Write-Host ("Проверено файлов: {0}" -f $files.Count)
Write-Host ("Ошибок: {0}, предупреждений: {1}" -f $errors.Count, $warnings.Count)

foreach ($warning in $warnings) { Write-Host "  ПРЕДУПРЕЖДЕНИЕ  $warning" }
foreach ($error in $errors) { Write-Host "  ОШИБКА         $error" }

if ($errors.Count -gt 0) { exit 1 }
exit 0
