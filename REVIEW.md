# kcl — глубокое ревью (2026-09-06)

Область: все 17 юнитов kcl (≈11 000 строк bash) + их тесты и документация; kklass только как
контракт, которому юниты должны следовать. Метод: 8 параллельных ревьюеров (по группам юнитов +
сквозной проход), каждая находка **воспроизведена командой** на bash 5.2.37 (часть — и на 5.3.9);
ключевые HIGH перепроверены вручную вторым проходом. Скрипты воспроизведения лежали в scratchpad
сессии (`kcl_review/g1..g8`) и в репозиторий не входят.

Исходное состояние: мастер-свип `kbool/tests/tests.sh` — **20 наборов / 3066 тестов / 0 FAIL**
на обеих версиях bash (kcl = 17 наборов, 2261 тест). Дерево репозитория после свипа не меняется.
То есть **все дефекты ниже живут под зелёными тестами**: тесты либо не покрывают кейс, либо
проверяют не то (`$? -eq 0`, «любой из двух ответов», подстрока).

Итог по числам: **~28 HIGH, ~45 MED, ~50 LOW.** Идентификаторы находок сохранены из отчётов
ревьюеров (G1-*, G2-*, T*, G3-*, TSH-*, TCA-*, M*, tregex T*, G6-*, G8-*), на них ссылается `PLAN.md`.

---

## 1. Сквозные проблемы (повторяются в нескольких юнитах)

| ID | Sev | Где | Суть |
|---|---|---|---|
| X-INJ (G1-02, G3-04, TSH-01, TCA-05, M4, tregex T2, G6-06, G8-06) | **HIGH** | tlist/tobjectlist/tstringlist, tarray.sort/binarySearch, tstringhelper (9 методов), tcustomapplication (EnvironmentVariable, start_at), dateutils (все числовые входы), math (divMod/sumInt/min-maxIntValue/randomRange), tregex (maxCount), tfile.integerToFileAttributes | Пользовательские индексы/числа попадают в `(( ))`/`${!x}` без проверки. `L.Get 'x[$(touch pwn)]'` **выполняет команду**; `L.Get abc` тихо читает элемент 0; `08`/`09` роняют арифметику (восьмеричный разбор). Валидируют правильно только tinifile, tqueuestack, tarray.indexOf/copy, math._parse_int, tstringhelper.toCharArray/copyTo. |
| X-ECHO (G1-13, G2-03, TSH-02, M12, G6-03) | **HIGH** | kklass `kk._return` (echo -n) + все echo-юниты | Значения `-n`, `-e`, `-E`, `-neE` теряются под `$()`: `$(L.Get 0)` → «», `string.trim " -n "` → «», `tfile.appendAllText f -n` **ничего не пишет**. Исправление в kklass одной строкой (`printf '%s'`) + `printf` в echo-юнитах. |
| X-SETU (G8-01, G1-14) | MED | все 17 юнитов + `kklass_pascal.sh:42` | Под `set -u` ни один юнит не загружается (`_X_SOURCED: unbound variable`); `.delete` класса без деструктора падает (`kklass.sh:536`). |
| X-SETE (M7, tregex T1, G8-07) | MED | math (Tier-A helpers), tregex (все члены кроме escape) | Под `set -e` вызов молча завершает скрипт: хвостовые `&& …` списки и `(( x++ ))` с 0. |
| X-CONTRACT (G8-05, G3-12, TSH-17) | MED | все | Три конвенции ошибок (silent-unless-debug / всегда stderr / никогда не падать) и **пять** конвенций булевых ответов (rc / RESULT=1 / RESULT="false" / stdout true-false / RESULT=-1). Шесть юнитов возвращают через stdout (dateutils, math, tstringhelper, tfile, tpath, tdirectory) — каждый вызов = fork 15–23 мс против 0.2–0.7 мс direct. |
| X-LOCALE (TSH-04, tregex T3, G8) | MED | tstringhelper, tregex, fpjson-to-be | Свип идёт с пустым `LANG`/`LC_ALL` → bash в C-локали: `${#s}` считает байты, `${s,,}` **портит UTF-8 на 5.2** (`ÄÖ` → мусор), `.` в regex не матчит многобайтный символ. Документация обещает символьную семантику. |
| X-LEAK (G1-01, M6/G8-02) | HIGH/MED | tlist/tobjectlist/tstringlist; math | `${inst}_items` никогда не освобождается при `.delete` (утечка + «предзаполненный» новый инстанс с тем же именем); math оставляет `/tmp/.math_fe_$$.awk` на каждый процесс (нет EXIT trap). |
| X-LOCALS (G1-08, TSH-10, G6-23, TCA-14, G8-04) | MED | tlist/tstringlist (`i`,`j`), tstringhelper (`i`,`arg`), tfile (`attr_parts`), tdirectory (`letter`), tcustomapplication (`_dummy_opts`), kklass (`p`,`sm`,`wm`) | Счётчики циклов и временные массивы — глобальные, затирают переменные вызывающего кода. |
| X-DASH (G6-11, T7) | MED | tfile, tdirectory, tinifile | `rm`/`cp`/`mv`/`cat`/`cd`/`mkdir` без `--`: `tfile.delete -f` → rc 0, файл остался; `tfile.readAllText -` читает stdin. |
| X-DOCS (G1-19, G8-10, T14, G8-09, G3-11) | LOW | 7 юнитов без README (tcustomapplication tdirectory tfile tlist tpath tstringhelper tstringlist) — docs = скрейп FPC/Delphi, описывают несуществующие члены; 8 леджеров говорят UNCOMMITTED при давно закоммиченных юнитах; tstopwatch README описывает форк свойств, которого больше нет (D1 kklass). |

## 2. По юнитам

### 2.1 tlist / tobjectlist / tstringlist / tarray (G1) — 107+31+160+80 тестов зелёные
- **G1-01 HIGH** `${inst}_items` не освобождается (нет деструктора TList; TObjectList.Destroy без `inherited`).
- **G1-02 HIGH** X-INJ: индексы в `(( ))` в ~20 точках tlist/tobjectlist/tarray.
- **G1-03 HIGH** TStringList.Add применяет Duplicates к **несортированному** списку (FPC — только при Sorted) и делает O(n) IndexOf через kklass-диспетчер на каждый Add: 300 Add = **15.5 с** (TList 0.1 с).
- **G1-04 HIGH** `sorted = true` на заполненном списке не сортирует → Find/Add дают мусор.
- **G1-05 HIGH** dupIgnore Add возвращает **чужой** RESULT (`RESULT=x; return` минует трейлер func).
- **G1-06 MED** TList.Add возвращает count, TStringList.Add — index; FPC и docs — index.
- **G1-07 MED** TObjectList: `count = N` (shrink), `capacity < count`, Assign → владеемые объекты утекают или освобождаются перед rc 1.
- **G1-09 MED** capacity принимает отрицательные и < count: тихое усечение (FPC — EListError).
- **G1-10/11 MED** TStringList.Assign не копирует флаги; Assign/AddStrings форкают `$($source.count)`.
- **G1-12 MED** TArray: опечатка в имени компаратора тихо трактуется как start-индекс → сортировка по байтам.
- **G1-15..19 LOW** binarySearch без клампа диапазона; loose booleans в TObjectList; тест 015 не может упасть; Clear делает двойную работу; docs = Delphi-дамп.

### 2.2 tdictionary / thashset / tqueuestack (G2) — 130+23+76 зелёные
- **G2-01 HIGH** thashset: `unset "${inst}_items[$pk]"` в **двойных** кавычках → Remove/Extract тихо не удаляют элементы с `]`, `[`, кавычками, `\`, `$`; `$(…)` в элементе **выполняется**. tdictionary использует правильную одинарную идиому; PLAN thashset утверждает «идиомы взяты verbatim» — неправда.
- **G2-02 MED** tqueuestack/thashset ToArray без проверки имени выходного массива: зарезервированное имя удваивает хранилище (Count 2→4), пустое/плохое имя — rc 0.
- **G2-04 MED** thashset.Assign принимает любой инстанс с `_items` (TQueue → хранилище портится).
- **G2-05..10 LOW** ForEach без проверки callback; drift docs/README; лишние `source kerr/klib`; RESULT_KEY-глобал; разные состояния инстанса после отвергнутого токена конструктора (queue owning / dict non-owning).
- tdictionary: дефектов не найдено (15 экзотических ключей через все пути, ownership = FPC, 0 форков). tqueuestack: fuzz 4000 операций против эталона = ок.

### 2.3 tinifile (T) — 84 зелёные
- **T1 HIGH** `UpdateFile` на путь-**каталог**: rc 0, dirty сброшен, ничего не записано, tmp-мусор в каталоге.
- **T2/T3 MED** дыры валидации: ident `[x` + value `y]` при flush становится секцией (ключ пропадает); секция `[;name]` теряет все ключи при первом UpdateFile. PLAN 2.7 обещает отклонять то, что FPC портит.
- **T4 MED** SectionExists = true для пустых/comment-only секций (FPC false; docs говорят «same»).
- **T5 MED** eager DeleteKey/EraseSection глотают rc неудачного flush.
- **T6 MED** поиск ключа сканирует все строки всех секций + вызов функции на строку: 800 append = 13 с, чтение в 20-й секции 11 мс.
- **T7/T8 MED** tmp-файл течёт при неудачной замене; `--` нет; read-only файл молча заменяется и теряет права.
- **T9..T14 LOW** ifoEscapeLineFeeds последняя строка; `\`-хвост значения; StrToIntDef (пробелы, `x1F`); Windows-пути `\`; имена выходных массивов; drift леджера.

### 2.4 dateutils / tstopwatch (G3) — 123+34 зелёные
Ядро проверено независимо: ISO год/неделя/день **15 006 дат 1995–2035 vs perl — 0 расхождений**; weeksInAYear 1900–2100 — 0; round-trip всех encode/decode — 0 ошибок; локальная запятая в EPOCHREALTIME обработана в обоих юнитах.
- **G3-01 HIGH** поля с ведущим нулём (`08`, `09`) — `encodeDate 2011 08 09` падает, `isValidDate 2011 08 15` → **false**. Типичный вход из `IFS=- read y m d`.
- **G3-02 HIGH** `iso8601ToDate`/`tryISOStrToDateTime` принимают `2011-02-31` (→ 03-03), год 0000; FPC отвергает. Date-only вход валидирует правильно — несогласованность внутри юнита.
- **G3-03 MED** отрицательный MJD печатается как `0.-500000`, обратно не парсится.
- **G3-04 MED** X-INJ + пустая строка тихо = эпоха.
- **G3-05 MED** локальный offset всегда **текущий**, не на дату (DST); FPC — на дату. `printf '%(%z)T' <epoch>` даёт нужное без форка (SUSPECTED: на этой машине нет DST-зоны для репро).
- **G3-06..10 LOW** отрицательные поля интервала; крэш вместо rc 1 на мусорном JD; `hh:mm` в scanDateTime = месяц (FPC: минуты после часов); компактные ISO-формы; год 10000 без проверки.
- **G3-11 LOW** tstopwatch README описывает форк 17.7 мс на чтение свойства — устарело после D1 kklass (сейчас 0.87 мс без форка).
- **Все 185 членов dateutils — `proc` через stdout**: `$(dateutils.yearOf k)` = 15 мс на MSYS против 0.17 мс direct.

### 2.5 tstringhelper / tcustomapplication (G7) — 393+320 зелёные «потому что тесты проверяют не то»
tstringhelper:
- **TSH-01 HIGH** X-INJ в 9 методах (substring/remove/insert/chars/isDelimiter/pad*/indexOf*/lastIndexOf*/create).
- **TSH-02 HIGH** echo глотает `-n`/`-e`.
- **TSH-03 HIGH** `split` возвращает **соединённую обратно строку** (`split 'a,b,c' ','` → `a,b,c`), теряет всё после первого `\n`; тест 037 проверяет `*a*`.
- **TSH-04 HIGH** X-LOCALE: байтовая семантика по умолчанию, `toLower 'ÄÖ'` → мусор на 5.2.
- **TSH-05..10 MED** replace по умолчанию первое вхождение (FPC — все); lastIndexOf математика StartIndex/Count неверна (тесты принимают «любой из двух»); toBoolean только `true`/`1`; quotedString не дублирует кастомную кавычку + fork `echo|sed` + теряет хвостовые `\n`; O(n·m) циклы: 10 KB replace/indexOf = 520–600 мс против 0.36 мс через `${s//…}`; глобальные `i`/`arg`.
- **TSH-11..19 LOW** отрицательные индексы ≠ FPC Copy; trim не режет control chars; indexOf('') Delphi vs FPC; toInteger '3.9'→3; format; copyTo с именем локала; контракт stdout; toDouble без валидации; getHashCode зависит от локали.
tcustomapplication:
- **TCA-01 HIGH** `--opt=value` (единственный FPC-синтаксис значения long-опции) не распознаётся; тесты закрепили обход `verbose=true`.
- **TCA-02 HIGH** `:`/`::` в ShortOptions/LongOpts вырезаются и игнорируются; значения не потребляются (`GetNonOptions` считает их non-options).
- **TCA-03 HIGH** `ParamCount`/`Params` читают `$#`/`${!i}` **самого метода**: всегда 0/«»; тесты 008/011 под `if ParamCount>0` → никогда не выполняются.
- **TCA-04 HIGH** без SetArgs первый вызов опционного метода сохраняет **свои аргументы** как argv приложения (идиома теста 019 «работает» случайно).
- **TCA-05 HIGH** X-INJ через `${!var_name}` в EnvironmentVariable.
- **TCA-06..11 MED** CaseSensitiveOptions хранится, не используется; GetOptionValues отдаёт lossy `count:v1 v2`; LongOpts массив-vs-строка зависит от других параметров; AllErrors игнорируется; **нет DoRun**, Run = busy-loop с форком каждые 10 мс, неостановимый из фона; Location возвращает каталог kklass.
- **TCA-12..20 LOW** Terminate экспортирует EXITCODE в окружение детей; `-`/`--` семантика; глобал `_dummy_opts`; GetEnvironmentList `env|sort` + значения с `\n`; Log без формата и на stdout; first-vs-last occurrence; тексты ошибок ≠ FPC; мёртвый код; OnException с пробелами.

### 2.6 math / tregex (G4) — 81+190 зелёные
math (awk co-process):
- **M1 HIGH** любая фатальная ошибка awk (деление на 0: `fmod x 0`, `cotan 0`, `logN 1 x`, `mean` без аргументов, `intPower 0 -1`, …) **убивает движок**; вызов возвращает пустую строку с rc 0; следующий вызов молча респавнит awk + предупреждение bash в stderr.
- **M2 HIGH** `frexp inf|nan|1e308` — **вечное зависание** вызывающего шелла (`read` без `-t`).
- **M3 HIGH** `\n` в аргументе рассинхронизирует pipe навсегда: все последующие ответы сдвинуты на один.
- **M4 HIGH** X-INJ + `08` в divMod/sumInt/minIntValue/randomRange/_num_cmp.
- **M5 MED** собственные токены `inf`/`nan` gawk читает как 0 (`max inf 1` → 1, `isZero inf` → true); движок реально выдаёт `+inf`/`-nan`.
- **M6 MED** X-LEAK temp-файл. **M7 MED** X-SETE. **M8 MED** тихий 64-битный wrap на «точных» путях (`intPower 2 63` → отрицательное). **M9 MED** предупреждение coproc при респавне.
- **M10..M15 LOW** без awk публичные методы дают пустую строку rc 0 (README обещает non-zero); `-0` из roundTo; echo `-n`; randomRange 30-битный; мусор на входе принимается; `LC_ALL=C` не форсирован для awk.
tregex:
- **T1 MED** X-SETE во всех членах кроме escape. **T2 MED** X-INJ через maxCount. **T3 MED** X-LOCALE: docs утверждают обратное. **T4 MED** zero-length anchored (`$`, `\b`, `\<`) дают len+1 ложных совпадений в matches/replace/split (`replace "abc" '$' '!'` → `!a!b!c!`); S6 в docs утверждает «correctness unaffected».
- **T5..T10 LOW** флаги через `*i*` (`Multiline` включает ignore-case); escape O(n²) (50 KB = 14 с); скан копирует остаток на каждый матч (4000 матчей = 2.1 с); плохое имя выходного массива → rc 0; `$()` режет хвостовые `\n`; `$10` = `$1`+`0`.

### 2.7 tfile / tpath / tdirectory (G6) — 120+112+197 зелёные; 12 symlink-тестов **всегда PASS (skipped)**
- **G6-01 HIGH** tpath: `\` не считается разделителем в getFileName/getExtension/getPathRoot (класс `[$SEP$ALT]` → `[\/]` = только `/`). `combine /c/tmp file.txt` → `/c/tmp\file.txt`, который сам tpath распарсить не может.
- **G6-02 HIGH** `changeExtension` режет по последней точке **всего пути**: `/home/u/.config/app/file .bak` → `/home/u/.bak`; `dir.d/file .txt` → `dir.txt`.
- **G6-03 HIGH** X-ECHO: `appendAllText f -n` не пишет ничего.
- **G6-04 HIGH** `tdirectory.delete "link/"` удаляет **содержимое цели** симлинка и оставляет ссылку (семантика `rm -rf "lnk/"`).
- **G6-05 HIGH** `createSymLink` никогда не работает на MSYS (mklink получает POSIX-пути); тесты пропускаются, потому что probe `ln -s` на несуществующую цель падает.
- **G6-06 MED** X-INJ integerToFileAttributes. **G6-07 MED** tfile set*Time/setAttributes — тихие no-op, getAttributes всегда faNormal (tdirectory реализует по-настоящему). **G6-08 MED** *Utc-сеттеры сдвигают время на TZ (touch -t = local). **G6-09 MED** листинги без dot-entries, isEmpty считает их. **G6-10 MED** copy/move в существующий каталог вкладывает source внутрь. **G6-11 MED** X-DASH. **G6-12 MED** getDirectoryName для корня/хвостового `/`/смешанных разделителей ≠ FPC. **G6-13 MED** getFullPath: `realpath` без `-m` возвращает сырой относительный вход; `-e` → пусто. **G6-14 MED** FollowLink инвертирован (`stat -L` при false). **G6-15 MED** combine эмитит `\` на MSYS. **G6-16 MED** форки: `$(uname -s)` на каждый driveExists (45 мс), `$(ls -A)` в isEmpty (73 мс), вложенные `$(tpath.x)`. **G6-17 MED** рекурсия следует по dir-symlink → циклы.
- **G6-18..27 LOW** readAll*/writeAllBytes без byte-fidelity; replace не удаляет source; Windows-invalid chars принимаются; nocasematch затирается; combine и UNC; глобалы; exists игнорирует FollowLink; failglob ломает листинги; crypt temp в `$PWD`; нет re-source guard в tdirectory.

### 2.8 Сквозной проход (G8) и fpjson
- Загрузка всех 17 юнитов в один шелл: чисто (нет предупреждений kklass, `set -o`/`shopt`/IFS/traps не меняются, coproc math ленивый). Префиксы глобалов не пересекаются.
- **G8-01 MED** X-SETU. **G8-03 LOW** `kerr.sh`/`klib.sh` подключаются tlist/tdictionary/tstopwatch, но `ke.*` не вызывается **нигде** в kcl. **G8-04 LOW** kklass течёт глобалами `p sm wm METHOD_BODY METHOD_WRAPPER`.
- **G8-08 LOW** тесты со `sleep` и фиксированными именами в `/tmp` под 8 параллельными воркерами ktests.
- **G8-09 LOW** 8 леджеров со статусом UNCOMMITTED при закоммиченных юнитах.
- **`.ckk`**: каталоги под kcl (`kcl/.ckk`, tinifile, tlist, tqueuestack) созданы kklass-тестами 030/063/065, пишущими в `$PWD`, когда свип запускали из каталога юнита; `**/.ckk` в `.gitignore` — правильная симптоматическая мера, корень — в kklass-тестах.
- **fpjson (PLAN = DRAFT)**: модель (B) «инстанс документа + целочисленные handle в параллельных массивах» — верна (10k узлов = 90 мс; объект-на-узел = 10k инстансов × 15 функций — неприемлемо). Две поправки: детей хранить списком id в `${doc}_kids[id]` (не `\x1f`-строкой), добавить `_parent[id]`, освобождать все суффиксы в деструкторе. **Допущение плана о парсере неверно**: `${s:i:1}` по большой строке — O(n) на доступ, посимвольный цикл 96 KB = **45 с** на 5.2; оконный regex-лексер (`[[ $window =~ ^(token) ]]`, окно 2 KB) — 1.7 с и токены целиком (escape-обработка раз на строку). `printf '\U…'` для astral и суррогатов в этой среде печатает литерал → UTF-8 кодировать вручную; лексер под `LC_ALL=C`.

## 3. Что в тестах не так системно
- Ассерты «rc == 0», «непусто», «любой из двух», «подстрока» — tfile 030–036, tdirectory 027–029, tpath 009, tstringhelper 027/034/037, tcustomapplication 003/007/010/014/027; guard `if ParamCount>0` (008/011) — ветка никогда не выполняется; tstringlist 010 `kt_test_pass` безусловно; tstringlist 015 grep по несуществующему синтаксису.
- Нет ни одного теста: под `set -u`/`set -e`; под UTF-8 локалью; с нечисловыми/инъекционными индексами (кроме tstringhelper/059 и tcustomapplication/018 — не для числовых параметров); на освобождение `${inst}_items`; на значения `-n`/`-e` через `$()`; на большие входы (перф-стенки 10–15 с невидимы).
- 12 symlink-тестов tfile всегда «PASS (skipped)».

---

## 4. Статус после P0–P10 (дописано фазой P9, строка P10 — фазой P10, 2026-09-09)

Карта «находка → фаза», строго по `closed`-картам `kcl_ledger.json`. Сами находки
здесь не пересказываются — только где закрыто и чем.

| Фаза | Что закрыто | Комментарий |
|---|---|---|
| **P0** — фундамент | D1, D6, G1-13/G2-03 (X-ECHO в ядре), G1-14, G8-01, G8-04, R15 | правки в kklass (`kk._return` → `printf '%s'`, `.delete` под `set -u`), kkore (`kk.isInt`/`kk.isNum`), ktests (`LC_ALL=C.UTF-8`), новый `kcl/README.md` с контрактом |
| **P1** — сквозной hardening 17 юнитов | X-INJ: G1-02, G3-04, TSH-01, TCA-05, M4, tregex T2, G6-06, G8-06 · X-LOCALS: G1-08, TSH-10, G6-23, TCA-14 · X-DASH: G6-11, T7 · X-SETU: G8-01 · X-SETE: M7, tregex T1, G8-07 · X-ECHO: TSH-02, M12, G6-03 · R14/G8-03 | шесть сквозных классов дефектов, по одному проходу на класс |
| **P2** — контейнеры | G1-01…G1-19 (кроме docs-половины G1-19, см. P9), G2-01, G2-02, G2-04, G2-05, G2-06, G2-07, G2-10; умолчания R1–R5 | + найдено и исправлено здесь же: **P2-F2** |
| **P3** — файловая система | G6-01…G6-27, D3, D5, D6, R13 | 12 symlink-тестов «PASS (skipped)» стали настоящими |
| **P4** — tcustomapplication | TCA-01…TCA-20 (D4: построчный порт FPC 3.2.2 `custapp.pp`) | 18 тестов, закреплявших старый диалект, переписаны |
| **P5** — tstringhelper | TSH-03…TSH-19 (R9) | 13 тестов переписаны; **P5-F2** закрыт по замечанию ревьюера |
| **P6** — dateutils + tstopwatch | G3-01…G3-12, D3 + R8 + D6 | **P6-F1** потребовал правки kklass |
| **P7** — math + tregex | M1…M15, tregex T3…T10, D3 + R8 (R11, R12) | M4, M7, M12(echo), tregex T1/T2 — проверено, что закрыты в P1 |
| **P8** — tinifile | T1…T14, D6 | + сверх списка: ведущий комментарий забирает следующие ключи (FPC `FillSectionList`) |
| **P9** — документация и леджеры | G8-09, G8-10; docs-половина G1-19, G3-11, G2-06, G2-07 — проверена и добита; **P8-F1** исправлен | `kcl/README.md` §2 (таблица юнитов + контракт каждого), README для thashset, шапки «ported / roadmap / wontfix» во всех `docs/*.md`, статусы 10 леджеров, два общих хелпера в kkore (`kk.debug`, `kk._outName`) |
| **P10** — fpjson P0: перепланирование | G8 task 5 (обзор проекта fpjson) — единственная находка ревью, которая закрывается не правкой кода, а ПЛАНОМ | `fpjson/PLAN.md` переписан целиком (737 строк, флаг DRAFT снят) под D8: модель узлов (B) с шестью массивами документа и монотонными хендлами, оконный гибридный лексер с `LC_ALL=C` в его области, явный стек с откатом по водяному знаку, грамматика FindPath по трём `DoFindPath`, байтовый паритет `AsJSON`, `ParseFile` через `mapfile -d`, построчная сверка с контрактом `kcl/README.md` §1, фазы P1–P8, решения D8-1…D8-6, три вопроса владельцу. Новая проба `fpjson/bench/lexer_probe.sh`: посимвольный разбор целого документа 96 KB = 38,7 с на 5.2.37, оконный гибрид 20 KB = 290 мс при гейте 1 с. Кода юнита нет — фаза плановая |

### Находки, найденные во время работ (`found_in_*`)

| ID | Где | Статус |
|---|---|---|
| **P2-F1** | `TList.BatchInsert`/`BatchDelete` объявлены `proc`, но тело кладёт новый count в `RESULT` — значение не доходит до вызывающего | **открыта.** Нужно решение владельца: сделать их `func` или убрать присваивание. README юнита описывает текущее поведение (только rc), так что ложного обещания нет |
| **P2-F2** | tdictionary: старая проверка имени выходного массива принимала любое зарезервированное имя (`d.KeysToArray __td_items` стирал словарь и возвращал rc 0) | **исправлена в P2** (`TDict._outName` + `TDict._isAssoc`, rc 2) |
| **P3-F1** | `cd -- -` всё равно означает `$OLDPWD` — `--` в P1 закрыл только половину G6-11 | **исправлена в P3** (`./-`), тест `034_G6_Lifecycle.sh` |
| **P3-F2** | `tpath.getTempPath` читал `$TMPDIR` без `:-` и умирал под `set -u` | **исправлена в P3** |
| **P3-F3** | скрипт ревью `repro/g6/probe_tdir.sh` оставлял `w_tdir/` в репозитории | **не исправлена**: это материал ревью, а не код продукта |
| **P4-F1** | kklass: чтение хранимого (`var`) свойства под `set -u` роняло вызывающего (`kk._property` / `kk._prop_plain` тестировали `$3`/`$4` на пути ЧТЕНИЯ) | **исправлена в kklass** `5ad097e`, тест `kklass/tests/128_SetUContract.sh` |
| **P4-F2** | ktests: временный каталог теста звался по `basename $0`, а под раннером `$0` = `bash` — восемь параллельных файлов делили `.tmp/bash` и сносили его друг у друга | **исправлена в ktests** `e4dfd8c` (раннер передаёт путь файла как `$0`) |
| **P5-F1** | `string.compare`/`compareOrdinal`/`compareTo` сравнивают строки ЦЕЛИКОМ; FPC `Compare` — префиксное сравнение по `min(Length(A),Length(B))`, и `CompareTo` — байтовое | **открыта**, задокументирована в `tstringhelper/README.md` §3.3. Смена семантики требует слова владельца (на целых строках построены тесты 002/003/005) |
| **P5-F2** | `endsText`/`startsText`: пустой subtext — FALSE у `TStringHelper`, TRUE у `StrUtils.Ansi*` | **исправлена в P5** по замечанию ревьюера (побеждает `TStringHelper`) |
| **P6-F1** | kklass: вычисляемое свойство, реализованное методом, не могло вернуть ненулевой статус — сгенерированный шим терял его | **исправлена в kklass** `32f4232`, тест `kklass/tests/130_ComputedPropertyStatus.sh` |
| **P6-F2** | осиротевшие деревья процессов удваивают время наборов и дают ложные таймауты | **не дефект дерева**: проверять `ps -W` перед любым замером |
| **P7-F1** | gawk 5.0.0 не следует IEEE для NaN (`x != x` ложно): проверка NaN самонеравенством неверна | **учтена в math** (`sprintf("%g")` + `index(s,"nan")`); вне math не встречается |
| **P7-F2** | `${var//pat/rep}` квадратичен по длине субъекта на 5.2.37 и 5.3.9 (10/20/40/80 KB → 11/48/183/712 мс) | **открыта и не исправима**: линейной чисто-bash альтернативы нет. Записана, чтобы «это O(n)» больше не писали |
| **P7-F3** | `read -t` стоит ~410 мкс за вызов при любом таймауте (≈4× обычного `read`) | **открыта**: платит любой горячий путь с таймаутным чтением |
| **P7-F4** | два простаивающих bash-дерева под харнессом — проверены, CPU ≈ 0, это не runaway из P6-F2 | закрыта наблюдением |
| **P7-F5** | `tstringlist/tests/013_AssignOptimization.sh` держал АБСОЛЮТНУЮ стенку в миллисекундах (`elapsed_ms < 200`) — ровно та форма, которую запрещает PLAN §4; под восемью воркерами раннера мигал | **исправлена в коммите P7 `caae508`**: в `013` теперь относительный гейт (Assign 50 элементов ≤ 3× стоимости 50 поштучных Add, +50 мс запаса), сосед `018` считает best-of-3. Проверено по дереву при ревью P9 |
| **P8-F1** | семь юнитов носили по своей копии проверки имени выходного массива | **исправлена в P9**: `kk._outName NAME [PREFIX…]` в `kkore/klib.sh`, принята всеми семью |
| **P8-F2** | ktests: каталоги фикстур по-прежнему именуются значением, переданным в `kt_test_init` — файл, забывший передать литерал, снова получает общий `.tmp/bash` | **открыта**: у tinifile обойдено локально, каркасная правка — за ktests |
| **P9-F1** | `thashset/README.md`, написанный в этой фазе, сам содержал дрейф (`s.count` как свойство против объявленного `func Count`) — поймано скриптовой сверкой имён | закрыта на месте; сама сверка (README/docs против объявления класса, в обе стороны) стоит секунд и ловит то, чего не видит чтение |
| **P9-F3** | HIGH: проба ассоциативной цели `${ref@a}` падала под `set -u` в ТРЁХ юнитах — nameref на объявленный, но не получивший значения массив считается unbound, а `declare -a out=()` это ровно он. tinifile закрыл это в P8 (`local -; set +u`), у thashset, tqueuestack и tdictionary осталась голая форма. Репро: `bash -c 'set -eu; source kcl/thashset/thashset.sh; THashSet.new S; S.Add x \|\| true; declare -a out=(); S.ToArray out'` → `__ts_out: unbound variable`; аналогично `Q.ToArray out` (`tqueuestack.sh:206`) и `D.KeysToArray out` (`tdictionary.sh:431`, `TDict._isAssoc`) | **исправлена в P9** по замечанию ревьюера (внесена НЕ этой фазой — проверено против закоммиченного `thashset.sh`). Проба вынесена в локальный хелпер с `local -; set +u`: `TSet._isAssoc`, `TQueueStack._isAssoc`, две строки в `TDict._isAssoc`. Тесты — по два `set -eu`-кейса в контрактный файл каждого юнита, красные 2/2/2 до правки |
| **P10-F1** | префикс `VAR=value` перед `bash.exe` (msys→cygwin) НЕ доходит до потомка: первый прогон пробы на 5.3.9 получил `LC_ALL` пустым и сгенерировал документ другого размера (2103 против 2081 байта), потому что `${#j}` считал символы. Репро: `PATH="/c/bin/msys64/usr/bin:$PATH" LC_ALL=C.UTF-8 /c/bin/msys64/usr/bin/bash.exe -c 'echo [${LC_ALL:-unset}]'` → `[unset]`; то же через `env LC_ALL=C.UTF-8 …` → `[C.UTF-8]` | **обойдена**: генератор пробы фиксирует `LC_ALL=C` сам, поэтому вход побайтово одинаков в обеих версиях. Правило «локаль для 5.3.9 задавать через `env`» записано в леджер; в §0 плана его стоит добавить, если появится ещё один дуальный прогон |
| **P10-F2** | черновик `fpjson/PLAN.md` цитировал номера строк FPC из trunk (fpjson.pp 4322, jsonscanner.pp 758, jsonparser.pp 290), а не из тега `release_3_2_2` (4108 / 616 / 275, плюс jsonreader.pp 631) | **исправлена в P10**: все ссылки перечитаны по тегу и приведены в форме `fpjson.pp:NNN`. Побочно: старый файл содержал 3 байта NUL и считался git бинарным — в переписанном их нет |
| **P10-F3** | утверждение отчёта G8 «`printf '\U0001F600'` и одиночные суррогаты печатаются БУКВАЛЬНО в этом окружении» верно только в локали C | **уточнена в P10**: под `LC_ALL=C.UTF-8` обе версии печатают правильные 4 байта; буквальными они становятся внутри `local LC_ALL=C`, то есть ровно в области лексера (`\u00e9` там даёт голый байт `e9`). Вывод отчёта (кодировать UTF-8 вручную) не меняется, причина в `fpjson/PLAN.md` §4.4 |

### Закрытие открытых находок (2026-09-09, решения владельца)

| Находка | Решение | Что сделано |
|---|---|---|
| P2-F1 tlist BatchInsert/BatchDelete | rc-only | мёртвые `RESULT=` убраны, пин в 020_Contract |
| P5-F1 tstringhelper compare* | целиком, compareTo побайтово | `local LC_ALL=C` в compareTo, тест 067, README §3 |
| P9-F4 tdictionary KeysToArray/ValuesToArray/ToArrays | count в RESULT | func + RESULT=count, 014_Contract +3 |
| P8-F2 ktests fixture dir | от имени файла | `kt_test_init` → `<name>.<file>`, тест 032 |
| fpjson O1/O2/O3 | строгий RFC, пер-документ, handle | зафиксировано в fpjson/PLAN.md §15 |

Информационные, без действия: P7-F1 (gawk NaN, обработано в math), P7-F2 (`${var//}` квадратичен в bash), P7-F3 (`read -t` ~410 мкс), P6-F2 (осиротевшие процессы), P3-F3 (repro-скрипт оставляет каталог).
