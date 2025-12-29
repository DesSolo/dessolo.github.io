---
title: 'Бинарные зависимости в проектах: единый подход для команды'
date: '2025-12-26T23:34:35+03:00'
description: >-
  Как стандартизировать установку инструментов (golangci-lint, goose, goreleaser и др.) 
  в multi-ОС команде с помощью Makefile и локальных бинарников.
categories:
  - Tutorial
tags:
  - go
  - tooling
  - make
draft: false
---

Когда над проектом работает несколько человек - особенно с разными ОС (Linux, macOS, *иногда даже Windows*), - быстро возникает **разнобой в инструментах**:  
один использует `golangci-lint` v2.5.0, другой - v2.7.2, третий вовсе забыл его обновить.  
В итоге:  
- локально всё ок, а на CI - ошибки
- `goose migrate` работает у одних, падает у других
- коллеги тратят время на «а у меня не запускается»

**Цель**: сделать установку и версионирование *бинарных* (pre-compiled) зависимостей **предсказуемой и воспроизводимой** - без глобальных `go install`, `brew` или `apt`.

---

## Почему именно бинарники?

- Не требуют компиляции
- Изолированы от глобального окружения
- Контролируемая версия
- Работает вне GOPATH

---

## Предлагаемая структура

```shell
.
├── Makefile # точка входа и версии
├── bin # локальные бинарники (игнорируется в .gitignore)
└── scripts
    ├── install.mk # установка инструментов
    ├── generate.mk # (опционально) запуск линтеров
    └── tests.mk # (опционально) миграции через
```

---

## Makefile: точка входа и управление версиями

```make {file="Makefile"}
LOCAL_BIN := $(CURDIR)/bin

LINT_VERSION := v2.6.1
GOOSE_VERSION := v3.16.0
GORELEASER_VERSION := v2.3.0

include scripts/*.mk
```

---

## install.mk: установка бинарных файлов

```make {file="scripts/install.mk"}
OS := $(shell uname -s | tr A-Z a-z)
ARCH := $(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

.prep_bin:
	mkdir -p ${LOCAL_BIN}

.install-lint:
	curl -Ls https://github.com/golangci/golangci-lint/releases/download/v${LINT_VERSION}/golangci-lint-${LINT_VERSION}-${OS}-${ARCH}.tar.gz | \
		tar xvz --strip-components=1 -C ${LOCAL_BIN} golangci-lint-${LINT_VERSION}-${OS}-${ARCH}/golangci-lint

.install-goose:
	curl -Ls https://github.com/pressly/goose/releases/download/${GOOSE_VERSION}/goose_${OS}_${ARCH} --output ${LOCAL_BIN}/goose
	chmod +x ${LOCAL_BIN}/goose

.install-goreleaser:
	curl -Ls https://github.com/goreleaser/goreleaser/releases/download/${GORELEASER_VERSION}/goreleaser_${OS}_${ARCH}.tar.gz | tar xvz -C ${LOCAL_BIN} goreleaser

.PHONY:install-deps
install-deps: \
	.prep_bin \
	.install-lint \
	.install-goose \
	.install-goreleaser
```

> - `OS` и `ARCH` определяются динамически, но можно переопределить:  
> `make OS=linux ARCH=arm64 install-deps`
> - Для Windows (если нужно) - добавьте обработку `MINGW*/CYGWIN*` в `uname -s`
{ .prompt-info }

---

## Как использовать

```bash
make install-deps
```

---

## Заключение

Управление бинарными зависимостями через Makefile - это просто, надёжно и масштабируемо.

Вы получаете:
- единый стандарт для всей команды
- воспроизводимость «на любой машине»
- независимость от глобального окружения

А главное - меньше «а у меня работает».
