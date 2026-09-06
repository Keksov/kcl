# kcl — план доработок по ревью 2026-09-06

Источник: `REVIEW.md` (находки с ID), решения владельца D1–D8 (2026-09-06), рекомендованные
умолчания R1–R15 (владелец может отменить любое до начала соответствующей фазы). Машинный журнал —
`kcl_ledger.json`. Конвенция та же, что у kklass/PLAN.md: фаза = ветка работ с гейтом; коммит
каждой фазы только по явному «go»/«коммить» владельца; сабмодуль kcl коммитится раньше kbool.

## 0. Для новой сессии: контекст, окружение, запуск

**Где что лежит.** `REVIEW.md` — сводка находок; `docs/review-2026-09-06/0N_*.md` — полные отчёты восьми ревьюеров с точными `file:line`, командами воспроизведения, «наблюдалось / ожидалось» и пробелами в тестах; `docs/review-2026-09-06/repro/gN/*.sh` — их скрипты (пути внутри могут указывать на scratchpad старой сессии — поправить `K=`/`source`); `docs/review-2026-09-06/00_BRIEF.md` — бриф ревью с контрактами kklass, по которым судили код. `kcl_ledger.json` — журнал фаз. Память сессии: `kcl-review-plan` в `~/.claude/projects/c--projects-kkbot-kbool/memory/`.

**Окружение.** Windows 11, MSYS2. Основной bash 5.2.37 = `bash` в PATH. Второй bash 5.3.9 (cygwin): `C:/bin/msys64/usr/bin/bash.exe`; наборы на нём запускать ТОЛЬКО так: `PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe tests/tests.sh` — без префикса PATH дочерний `bash` раннера оказывается msys 5.2 и набор сообщает 0 тестов. `python` в PATH — заглушка Microsoft Store, зависает; использовать perl/awk/sed. Локаль по умолчанию пустая (bash в C) — см. D6.

**Запуск тестов.** Набор юнита: `bash kcl/<unit>/tests/tests.sh [--verbosity info]` (ktests; на pass при verbosity по умолчанию печатает ничего; фильтр по имени файла — аргументом). Мастер-свип: `bash kbool/tests/tests.sh` (≈8–9 мин на версию; 20 наборов). Два набора/два bash — строго последовательно (гонка на `tests/.ckk` и `/tmp`). Итог смотреть grep-ом по ВСЕМ строкам `[FAIL]`, не по хвосту. Бенчи: `bash kcl/<unit>/bench.sh` там, где есть; правило — ни одна метрика не хуже; не перечислять таблицу функций большого шелла (`compgen -A function`) — замедляет весь процесс.

**Контракты kklass (актуально после kklass `b564029`, 2026-09-05).** `func` возвращает через `kk._return V` → `$RESULT`; direct-вызов НЕ печатает, под `$()` печатает ровно один раз; вычисляемые свойства — так же (D1 kklass). Статические методы со static-свойствами теряют состояние под `$()` — значение и в `REPLY`. Инстанс = `<inst>_data` + `<inst>_class` + обёртки `<inst>.<член>()`; `.delete` освобождает только это — дополнительные массивы юнита (`${inst}_items` и т.п.) освобождает деструктор юнита. Зарезервированные имена членов: `this __inst__ __class__ RESULT REPLY IFS __kk_*`. `inherited`/`.parent` — от класса-владельца тела; `.call` виртуальный. Fork в горячем пути = 1–16 мс на большом шелле.

**Состояние рабочего дерева на момент передачи (2026-09-06).** kcl: НЕ закоммичены `REVIEW.md`, `PLAN.md`, `kcl_ledger.json`, `docs/review-2026-09-06/`, `.gitignore` (`**/.ckk`), и незавершённый thashset (`thashset/thashset.sh`, `thashset/tests/`, `thashset_ledger.json` — P1 из P0–P4, продолжается по своему PLAN после правок G2-01/02/04/05). kklass и kbool синхронны с origin/main. Коммиты — только по явному «go»/«коммить»; сабмодуль раньше родителя.

**FPC-эталон.** Паритет сверять по исходникам FPC 3.2.2: `custapp.pp`, `inifiles.pp`, `dateutil.inc`, `stringl.inc`/`classes`, `syshelph.inc` (TStringHelper), `math.pp`, `generics.collections`. Локального чекаута в репозитории нет; ревьюеры брали исходники извне — при необходимости получить и зафиксировать путь здесь.

## 1. Решения владельца (2026-09-06)

| ID | Решение |
|---|---|
| **D1** | Числовые аргументы валидируются **общим хелпером** `kk.isInt` / `kk.isNum` в kkore (`klib.sh`), с нормализацией `10#`; нарушение = rc 1, без вывода. |
| **D2** | Контракт инстанс-юнитов: ошибка = **rc 1 + RESULT="" + stderr только под одним debug-переключателем** (`VERBOSE_KKLASS=debug`); булевы ответы = **rc**. |
| **D3** | **Все шесть** «печатающих» статических юнитов (dateutils, tstringhelper, math, tfile, tpath, tdirectory) переводятся с `proc`+echo на `func`+`kk._return` (direct = RESULT без форка; `$()` продолжает печатать). |
| **D4** | tcustomapplication: **верный порт FPC 3.2.2** `CheckOptions`/`FindOptionIndex`/`GetOptionValue` (`--opt=value`, `:`/`::`, CaseSensitiveOptions, AllErrors, тексты ошибок FPC, DoRun, ParamCount/Params); тесты, закрепившие старый диалект, переписываются. |
| **D5** | Разделитель путей на MSYS/cygwin: **POSIX** — `DirectorySeparatorChar='/'`; парсеры tpath принимают на входе и `/`, и `\`. Ожидания tpath 001/003/007 меняются. |
| **D6** | Локаль: **требуется UTF-8**; раннеры тестов пинят `LC_ALL=C.UTF-8`; юниты при загрузке экспортируют `LC_CTYPE=C.UTF-8`, если `LC_ALL`/`LC_CTYPE`/`LANG` пусты; тесты с не-ASCII перед искомым символом; fpjson-лексер локально пинит `C`. |
| **D7** | `set -e` и `set -u` — **общий контракт kcl**: гварды `${_X_SOURCED:-}`, `if`/`+= 1` вместо хвостовых `&&`/`(( x++ ))`, смоук-тест `set -eu` в каждом наборе. Булевые rc-методы под `set -e` вызываются через `if`/`||` — документируется. |
| **D8** | fpjson P0: **чистый bash** — handle-модель (инстанс документа + параллельные массивы) + **оконный regex-лексер**; awk-ускоритель остаётся в P8 плана fpjson. |

## 2. Рекомендованные умолчания (действуют, если владелец не отменит)

| ID | Умолчание | Находка |
|---|---|---|
| R1 | `TList.Add` возвращает **индекс** (FPC, docs, TStringList уже так) | G1-06 |
| R2 | `capacity < count` и `capacity < 0` → rc 1, состояние не меняется (FPC EListError); закрывает и утечку в TObjectList | G1-09, G1-07b |
| R3 | Отвергнутый токен конструктора (`TObjectQueue.new q bogus`, `TObjectDictionary.new d bogus`): инстанс создаётся **с умолчаниями** + rc 1 — одинаково в обоих юнитах, задокументировано | G2-10 |
| R4 | `AddOrSetValue k sameOwnedHandle` освобождает handle (FPC-паритет) + предупреждение в README | G2 Q2 |
| R5 | `Assign` проверяет класс операнда через `${src}_class` (тот же класс или потомок), не только наличие `_items` | G2-04, G2 Q3 |
| R6 | tinifile: **гибридная** валидация (отклонять на записи то, что FPC-ридер переинтерпретирует; loader verbatim); `SectionExists` = FPC (`not Empty`); persistence: `-d`/`! -w` гварды + `--` везде + tmp+mv; индекс поиска — вариант (a) (убрать вызов функции на строку и полное сканирование), (b) только если появится потребитель с >500 ключами; `\` в пути нормализуется для расчёта каталога | T1–T8, T12 |
| R7 | dateutils: локальный offset **на дату** через `printf '%(%z)T' <epoch>` (без форка); `now`/`today` без изменений | G3-05 |
| R8 | Булевы функции конвертируемых статиков: **rc** + `kk._return true|false` (совместимость с `$()`-вызовами) | X-CONTRACT |
| R9 | tstringhelper: `replace` по умолчанию **все** вхождения (FPC); `indexOf('')` = -1 (FPC); `toBoolean` = FPC TryStrToBool; `split` → выходной массив по nameref + count в RESULT; `trim` режет `<= #32` | TSH-05, 07, 12, 13, 03 |
| R10 | tcustomapplication: **последнее** вхождение опции побеждает (код FPC 3.2.2); `GetOptionValues` → выходной массив + count | TCA-17, TCA-07 |
| R11 | math: движок **никогда не умирает** — все деления в прелюдии защищены и возвращают `+inf`/`-inf`/`nan` как FPC; при реальной недоступности движка публичный метод = rc 1 + пусто; `read -t` как страховка от зависания; awk под `LC_ALL=C`; токены `inf`/`nan` нормализуются в `_fe`; программа передаётся через process substitution (если cygwin-проба пройдёт), иначе EXIT-trap | M1–M3, M5, M6, M9, M10, M15 |
| R12 | tregex T4 (anchored zero-length): сейчас **исправить docs S6/§4 + закрепить тестами**; детекцию — только если появится потребитель `\b`-токенизации | T4 |
| R13 | ФС-юниты: листинги **включают** dot-entries (FPC/.NET); рекурсия **не заходит** в dir-symlink; `delete` срезает хвостовые `/` и на симлинке удаляет только ссылку; tfile set*Time/setAttributes реализуются через общие хелперы с tdirectory (creation time → rc 1); добавляется `readAllTextVar NAME` (без форка, с хвостовыми `\n`); copy/move в существующий каталог = содержимое / rc 1 | G6-04, 07, 09, 10, 17, 18 |
| R14 | Мёртвые `source kerr.sh/klib.sh` убираются из tlist/tdictionary/tstopwatch (kerr не адаптируется) | G8-03 |
| R15 | `.ckk`: `**/.ckk` в `kcl/.gitignore` остаётся **и** kklass-тесты 030/063/065 переводятся на `KKLASS_CKK_DIR`/tmp; 4 устаревших каталога `.ckk` под kcl удаляются | G8 task 6 |

## 3. Фазы

Порядок = риск × использование. Каждая фаза: код → тесты → docs юнита → гейт → «go» владельца → коммит.

### P0 — Фундамент (kklass, kkore, инфраструктура тестов) — S
- kklass: `kk._return` → `printf '%s'` (G1-13/G2-03); `kklass.sh:536` `${!__kk_dv:-}` (G1-14); `kklass_pascal.sh:42` гвард под `set -u` (G8-01); `local p sm wm` (G8-04); тесты 030/063/065 → `KKLASS_CKK_DIR` (R15). Регресс-тесты: `$()` значения `-e`/`-n`; `.delete` под `set -u`; `set -u; source kklass_pascal.sh`.
- kkore/klib.sh: `kk.isInt NAME_OR_VALUE` и `kk.isNum` (D1) + тесты kkore.
- Раннеры: `kbool/tests/tests.sh`, `ktests.sh` — `LC_ALL=C.UTF-8` (D6); в шаблон юнита — блок самоподстановки локали.
- `kcl/README.md` (новый): **контракт kcl** — возврат (RESULT/rc), ошибки и debug-переключатель, булевы = rc, `set -eu`, локаль, числовые аргументы, зарезервированные имена выходных массивов, правило «без форков в горячих путях».
- Удалить устаревшие `kcl/**/.ckk`, закоммитить `.gitignore`.
- Гейт: kklass 273+новые, kkore, master 5.2 и 5.3.

**DONE 2026-09-06** (закоммичено по команде владельца после ревью второго круга; push НЕ делался). Красный-первым: 127 (6 FAIL), 128 (18 FAIL), 129 (5 FAIL), kkore 006 (96 FAIL / 0 PASS), ktests 030 (7 FAIL при закомментированном пине) — потом правки, потом зелёное. Гейт: kklass 324/324, kkore 331/331, ktests 308/308, мастер-свип 20 наборов / 3238 тестов / 0 FAIL на 5.2.37 И 5.3.9 (было 3066); kklass 335/335, kkore 334/334, ktests 308/308. Отличия от буквы плана: (1) `set -u` понадобился не в одной строке `.delete`, а ещё в 36 косвенных чтениях метаданных (`${!var}`) по kklass.sh/kklass_pascal.sh/kklass_decl.sh/kklass_serializable.sh плюс `${meth_index[$2]:-}`, `${6:-}`, `${2:-}` — иначе `source <unit>.sh` под `set -u` (D7) недостижим в P1; (2) гварды `${_X_SOURCED:-}` починены также в kkore (5 файлов) и ktests (5 файлов), потому что kklass грузит kkore, а каждый будущий `NNN_Contract.sh` грузит ktests под `set -eu`; (3) к 030/063/065 добавлен **031** — он писал `.ckk` в `$PWD` тем же приёмом (его `rm -f .ckk/\"$TEST_FILE\".sh` из-за буквальных кавычек ничего не удалял), в старых каталогах лежал его `test_031.kk`; (4) слабые ассерты 030/031 («Force ИЛИ Compiling», «runtime ИЛИ No compiled») переписаны на точные; (5) локаль пиньется в `ktests/ktest.sh` — единой точке, которую грузят оба раннера И каждый тест-файл, поэтому одиночный запуск файла ведёт себя как в свипе; (6) `kcl/README.md` помечен как **нормативный** контракт, а не описание текущего состояния. P0 затрагивает четыре сабмодуля (kklass, kkore, ktests, kcl) и родителя.

**Ревью второго круга (владелец, 2026-09-06).** Проверено по дереву, не по отчёту; «сначала красный» подтверждён stash-ем kklass.sh. Найден один реальный пропуск в зоне P0: `kerr.sh:5` — в ветке ПОВТОРНОГО source остался голый `"$1"` (исправлен был только хвостовой `${1:-}` на строке 146). Ветка не гипотетическая: kklass грузит kkore, а tlist/tdictionary/tstopwatch (и tstringlist через tlist) подключают `kerr.sh` ещё раз — то есть под `set -u` эти четыре юнита падали бы и после гвардов P1. Тест 128 промахнулся, потому что грузил каждый файл ровно один раз в свежем шелле; теперь он source-ит каждую точку входа kkore и kklass ДВАЖДЫ, плюс реальную форму «kklass, затем юнит» и путь `source kerr.sh set_trap`. Закрыто красным-первым (3 FAIL). Заодно: (a) `kk.isInt 5 __v` из-за динамической области видимости писал собственную локаль функции и возвращал rc 0 — все локали переименованы в `__kk_*`, а `kk._setOut` отвергает `__kk_*`/`__KK_*` (rc 2); (b) обе функции и `kk._setOut` без аргументов падали на `$1` под `set -u` — `${1:-}`/`${2:-}`; (c) в таблице README tregex исправлен на `TRegEx` / static (остальные 16 строк сверены прогоном по числу static- и инстанс-членов); (d) в 128 добавлен кейс булевого метода под `set -eu` через `if`/`||`/`!` — он был зелёным сразу, это закрепление правила README, а не багфикс; (e) в `kklass/PLAN.md` и `kklass_ledger.json` появилась запись `P6_kcl_review_P0` со ссылкой на источник, иначе следующая сессия по kklass не поймёт происхождения правок. Владелец одобрил отсев вне int64 в `kk.isInt`, удаление `kbool/.ckk` (сделано) при сохранении `kklass/tests/.ckk` и все четыре отклонения первого круга. Полный гейт прогнан заново, потому что `klib.sh` и `kerr.sh` грузит каждый kcl-юнит.

### P1 — Сквозной hardening всех 17 юнитов — M
- X-INJ: `kk.isInt` во всех ~40 точках (tlist/tobjectlist/tstringlist/tarray, tstringhelper, tcustomapplication, dateutils, math, tregex, tfile).
- X-ECHO: `echo` → `printf '%s\n'` во всех echo-юнитах (промежуточно, до D3-конверсии).
- X-SETU/X-SETE: гварды `${_X_SOURCED:-}` (17 юнитов), `if`/`+= 1` в math/tregex (M7, T1).
- X-LOCALS: `local` для `i j arg attr_parts letter _dummy_opts`.
- X-DASH: `--` перед путями в tfile/tdirectory/tinifile (G6-11, T7).
- R14: убрать мёртвые source kerr/klib.
- Тесты: в каждом наборе `NNN_Contract.sh` — `set -eu` смоук + инъекционный индекс + `-n`-значение через `$()`.
- Гейт: master 5.2 и 5.3, все `[FAIL]` через grep, ни один бенч не хуже.

### P2 — Контейнеры: tlist / tobjectlist / tstringlist / tarray + thashset / tqueuestack — L
- G1-01 деструктор TList (`unset ${inst}_items`), `inherited` в TObjectList.Destroy; G1-03/04/05 TStringList (Duplicates только при Sorted, `_setSorted` сортирует, IndexOf = Find при Sorted, `_cmpCore` без диспетчера, dupIgnore возвращает индекс); G1-06 R1; G1-07 overrides `_setCount`/`_setCapacity`/Assign в TObjectList; G1-09 R2; G1-10 Assign копирует флаги; G1-11 без форков (`${src}_data[count]`); G1-12 валидация компаратора TArray; G1-15 кламп binarySearch; G1-16 булевы токены; G1-17/18 тест 015, Clear.
- thashset: G2-01 (**одинарные кавычки в unset**, тесты Remove/Extract на экзотических элементах), G2-02 ToArray, G2-04 R5, G2-05 ForEach; правка PLAN/ledger thashset («verbatim»). Затем thashset продолжает свой роадмап (P2 set algebra → P4).
- tqueuestack: G2-02 ToArray; R3.
- tdictionary: G2-07 docs, R4 предупреждение.
- Перф-гейт: TStringList 300 Add < 10× TList; docs/TStringList.md и docs/TList.md урезаются до портированного подмножества (G1-19), Names/Values/Text/CommaText — в роадмап.
- Гейт: наборы tlist/tobjectlist/tstringlist/tarray/thashset/tqueuestack/tdictionary + master ×2 + бенчи.

### P3 — Файловая система: tfile / tpath / tdirectory — L
- D5 (разделитель `/`, парсеры принимают оба: G6-01/12/15/22); G6-02 changeExtension по имени файла; G6-03 printf; G6-04/17 symlink (R13); G6-05 createSymLink через `cygpath -w` + рабочий probe в тестах; G6-06; G6-07 сеттеры tfile (R13); G6-08 `touch -d @epoch`; G6-09 dotglob; G6-10; G6-13 `realpath -m --`; G6-14 FollowLink; G6-16 форки (`uname`, `ls -A`, вложенные `$()`); G6-18 `readAllTextVar`; G6-19..27.
- D3: конверсия tfile/tpath/tdirectory на `func`+RESULT (R8 для булевых).
- Тесты: tpath 001/003/007 под D5; setter-тесты сравнивают значения; hidden entries; existing dest; symlink dir в delete/recursion; `-`-имена; tpath 012 → `_KT_TMPDIR`.
- Гейт: 3 набора + master ×2.

### P4 — tcustomapplication: порт FPC custapp — M
- D4: FindOptionIndex/GetOptionAtIndex/CheckOptions по FPC 3.2.2 (TCA-01/02/06/09/17/18), ParamCount/Params из сохранённого argv (TCA-03), убрать `"$@"`-инициализацию (TCA-04), EnvironmentVariable валидация (TCA-05), GetOptionValues → массив (R10, TCA-07), LongOpts по `declare -p` (TCA-08), DoRun + Run без форка (TCA-10), Location (TCA-11), EXITCODE не экспортировать (TCA-12), `-`/`--` (TCA-13), TCA-14..20.
- Тесты: переписать ~25 закреплявших диалект; добавить `=value`, `:`/`::`, «needs an argument», регистр, AllErrors, ParamCount на свежем инстансе.
- docs/TCustomApplication.md — сверить с реализацией; README юнита.

### P5 — tstringhelper — M
- D3 конверсия (TSH-17) — снимает TSH-02; TSH-01 (P1); TSH-03 split → массив (R9); TSH-04 D6; TSH-05/07/12/13 R9; TSH-06 lastIndexOf; TSH-08 quotedString/deQuotedString FPC без форка; TSH-09 O(n) через `${s//…}`/`${t%%"$v"*}`; TSH-10 (P1); TSH-11 кламп; TSH-14/15/16/18.
- Тесты: 027/034/037 с однозначными ответами; не-ASCII перед искомым; 10 KB перф-гейт; direct-вызовы.
- README юнита (нет).

### P6 — dateutils + tstopwatch — M
- G3-01 нормализация `10#` на публичной границе + `kk.isInt`; G3-02 `_valid_date` в `_parse_iso`; G3-03 `_span_fixed` знак; G3-05 R7; G3-06..10 (валидации, `hh:mm` после часов, компактные ISO-формы, диапазон 1..9999).
- D3 конверсия 185 членов на `func`+RESULT (R8) — самый большой выигрыш по форкам в kcl.
- Тесты: `08`/`09` во все числовые входы; Feb 30/31; negative MJD; perl-свип ISO-недель как регресс (15k дат, ~40 с) — отдельный медленный тест по флагу; DST-тест с `TZ` если tzdata доступна.
- tstopwatch: G3-11 README (D1 kklass), тест locale-comma.

### P7 — math + tregex — M
- math: R11 (M1/M2/M3/M5/M6/M9/M10/M15), M4 (P1), M8 переполнение → движок, M11 `-0`, M12, M13 randomRange, M14 `_is_num` гейт; D3 конверсия публичных обёрток на `func`+RESULT (stdout сохраняется через kk._return под `$()`).
- tregex: T1 (P1), T2 (P1), T3 docs + тест локали, T4 R12, T5 флаги, T6 escape O(n), T7 документировать/оптимизировать скан, T8 nameref-валидация + reserved list, T9/T10 docs.
- Тесты: domain-boundary для каждой Tier-B функции; `frexp inf` с таймаутом; `\n` в аргументе; temp-файл после выхода; `set -e` смоук; anchored `$`/`\b`.

### P8 — tinifile — M
- T1 (`-d`), T2/T3 R6, T4 SectionExists FPC, T5 rc eager, T6 R6(a), T7/T8 persistence (R6), T9/T10/T11/T12/T13, T14 ledger.
- Тесты: каталог/RO/`-`-имя/tmp-очистка; пустые и comment-only секции; `[x`/`y]` и `[;x]`; относительный перф-гейт 800 vs 200 append.

### P9 — Документация и леджеры — M
- README (API-таблица + контракт) для 7 юнитов без него: tcustomapplication tdirectory tfile tlist tpath tstringhelper tstringlist; docs/*.md урезаются до портированного подмножества или получают шапку «справочник upstream, портировано: …».
- Статусы 8 леджеров (G8-09); tstopwatch README (G3-11); tdictionary/thashset drift (G2-06/07); tregex docs (T3/T4); math README (M6/M10).
- `kcl/README.md` дополняется таблицей юнитов и их контрактов.

### P10 — fpjson P0: перепланирование — S
- D8: переписать `fpjson/PLAN.md` — оконный regex-лексер (окно 2 KB, `[[ $w =~ ^(token) ]]`, `LC_ALL=C` в области лексера), явный стек вместо рекурсии, `_kids[id]` как список id, `_parent[id]`, деструктор освобождает все суффиксы, UTF-8 из code point вручную (astral/суррогаты), числа-как-литералы (+ `-0`, `1E400`, int64), политика дубликатов ключей на parse и serialize, max-depth, контракт ошибок = D2, FindPath-грамматика для имён с `.`/`[`, тест teardown 10k узлов.
- Бенч-проба как P0-гейт: 20 KB ≤ 1 с на 5.2 оконным лексером; сравнить с посимвольным.
- Только после этого — реализация по роадмапу fpjson.

## 4. Правило для тестов: сначала красный

Каждая находка из `REVIEW.md` получает регрессионный тест с её ID в имени или в `kt_test_start`. Порядок обязателен:
1. тест пишется **до** правки и запускается на текущем коде — он обязан **упасть** (если не падает, тест переписывается, а не правка откладывается);
2. затем правка, тест зеленеет;
3. в леджере у находки фиксируется имя теста.

Системно переписываются слабые ассерты (REVIEW.md §3): `$? -eq 0` → сравнение значения; «любой из двух ответов» → один ответ; `*a*`-подстроки → точное равенство; `if ParamCount>0` и подобные гварды убираются; безусловные `kt_test_pass` удаляются; symlink-probe в tfile переводится на существующую цель, чтобы 12 «PASS (skipped)» стали настоящими тестами. В каждый набор добавляется `NNN_Contract.sh`: загрузка под `set -eu`, инъекционный индекс, значение `-n` через `$()`, освобождение всех `${inst}_*` после `.delete`, не-ASCII перед искомым символом там, где есть строки. Перф-стенки закрываются относительными гейтами (например, 800 append < 10× 200 append), а не миллисекундами.

## 5. Гейты (каждая фаза)
1. Набор юнита(ов) фазы — 0 FAIL на bash 5.2.37 и 5.3.9 (последовательно, не параллельно).
2. `kbool/tests/tests.sh` — 0 FAIL на обеих версиях; читать **все** строки `[FAIL]` через grep, не хвост.
3. `bench.sh` юнита (где есть): ни одна метрика не хуже предыдущей фазы; для конверсий D3 — direct-вызов без форка подтверждён (`BASHPID` неизменен).
4. Смоук `set -eu` для затронутых юнитов (с P1 — в каждом наборе).
5. `git status` чистый после свипа; `.ckk`/`/tmp` не растут.
6. Коммит только по «go»; kcl раньше kbool.
7. Для каждой закрытой находки в леджере указан тест, и этот тест был красным до правки (п. 4).

## 6. Оценка объёма
S ≈ до полудня работы, M ≈ 1–2 дня, L ≈ 2–4 дня. Итого ≈ 3–4 недели последовательно; P2/P3/P4/P5 независимы друг от друга после P1 и могут идти в любом порядке по указанию владельца.
