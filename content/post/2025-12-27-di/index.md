---
title: 'DI контейнер конфигурации'
date: '2025-12-27T18:57:35+03:00'
description: >-
  Простой DI-контейнер на Go - минимализм в инициализации зависимостей без тяжелых фреймворков
categories:
  - Tutorial
tags:
  - go
  - di
  - architecture
draft: false
---

В последнее время я часто использую простой DI-контейнер для инициализации зависимостей при запуске приложения. Такой подход иногда называют *DI container*, *service locator* или *service provider*. Он особенно удобен, когда хочется избежать тяжеловесных фреймворков вроде `uber-go/fx` или `google/wire`, но при этом сохранить читаемость и порядок в коде.

Разумеется, у такого «ручного» решения есть свои ограничения:

- Приходится завершать программу через `os.Exit(1)` при ошибках инициализации - иначе сложно корректно обрабатывать ошибки на ранних этапах (включая вложенные зависимости).
- Не поддерживает циклические зависимости - приложение завершиться при их наличии.
- Не является потокобезопасным: если контейнер используется из нескольких горутин одновременно, возможны гонки (race conditions).

> Используйте этот подход, только если точно понимаете его ограничения и готовы их контролировать.
{ .prompt-warning }

## Почему это работает

Контейнер реализует ленивую инициализацию: зависимости создаются по требованию, но только один раз - при первом обращении.

Это позволяет:
- Избежать преждевременной загрузки ресурсов (например, соединения с БД).
- Четко выстроить порядок инициализации через зависимости методов (`Pool()` → `UsersRepo()` и т.д.).
- Писать компактный и локальный код без дополнительных зависимостей.

---

## Пример реализации

```go {file="internal/app/container.go"}
type container struct {
	config    *config.Config
	pool      *pgxpool.Pool
	usersRepo repository.Users
	carsRepo  repository.Cars
	server    *server.Server
}

func newContainer() *container {
	return &container{}
}

func (c *container) Config() *config.Config {
	if c.config == nil {
		configFilePath := os.Getenv("CONFIG_FILE_PATH")
		if configFilePath == "" {
			configFilePath = "config.yaml"
		}

		conf, err := config.NewConfigFromFile(configFilePath)
		if err != nil {
			fatal("failed to load config from file", err)
		}

		c.config = conf
	}

	return c.config
}

func (c *container) Pool() *pgxpool.Pool {
	if c.pool == nil {
		options := c.Config().Storage

		poolConfig, err := pgxpool.ParseConfig(options.DSN)
		if err != nil {
			fatal("failed to parse postgres config", err)
		}

		pool, err := pgxpool.NewWithConfig(context.Background(), poolConfig)
		if err != nil {
			fatal("failed to connect to postgres", err)
		}

		ctx, cancel := context.WithTimeout(context.Background(), healthCheckTimeout)
		defer cancel()

		if err := pool.Ping(ctx); err != nil {
			fatal("failed to ping postgres", err)
		}

		c.pool = pool
	}

	return c.pool
}

func (c *container) UsersRepo() repository.Users {
	if c.usersRepo == nil {
		c.usersRepo = repository.NewUsers(c.Pool())
	}

	return c.usersRepo
}

func (c *container) CarsRepo() repository.Cars {
	if c.carsRepo == nil {
		c.carsRepo = repository.NewCars(c.Pool())
	}

	return c.carsRepo
}

func (c *container) Server() *server.Server {
	if c.server == nil {
		c.server = server.NewServer(
			usecase.New(c.UsersRepo(), c.CarsRepo()),
		)
	}

	return c.server
}

func fatal(message string, err error) {
	slog.Error(message, "err", err)
	os.Exit(1)
}
```

---

## Использование в приложении

```go {file="internal/app/app.go"}
func (app *App) Run(ctx context.Context) error {
	di := newContainer()

	if err := di.Server().Run(ctx); err != nil {
		return fmt.Errorf("failed to run server: %w", err)
	}

	return nil
}
```

Сам `App` может быть легковесной обёрткой - например, для graceful shutdown или логгирования. Всё «тяжелое» спрятано в контейнере.

---

## Плюсы и минусы

| ✅ Плюсы | ❌ Минусы |
|---------|----------|
| Простота: всего ~50 строк кода | Нет поддержки циклических зависимостей |
| Никаких внешних зависимостей | Не thread-safe - не подходит для runtime-инжекции |
| Чёткий контроль над жизненным циклом | Требует ручного управления порядком инициализации |

---

## Альтернативы

- **[google/wire](https://github.com/google/wire)** - compile-time DI. Генерирует код. Нет рантайм-оверхеда, но требует настройки и понимания генерации.
- **[uber-go/fx](https://github.com/uber-go/fx)** - мощный фреймворк для DI и lifecycle-менеджмента. Подходит для больших приложений, но добавляет сложность.
- **Конструкторы с явной передачей зависимостей** - самый «чистый» подход (`server.New(pool, repo1, repo2, ...)`), но при росте проекта вызовы становятся громоздкими.

---

## Заключение

Такой простой контейнер - отличный выбор для большинства проектов. Главное - не забывать про его ограничения.