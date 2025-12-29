---
title: 'Удобные моки в Go: как упростить unit-тестирование'
date: '2025-11-05T09:56:52+03:00'
description: >-
  Практическое руководство по использованию мок-объектов в Go с помощью mockery и организации тестов через вспомогательные контейнеры.
categories:
  - Tutorial
tags:
  - go
  - testing
draft: false 
---

Unit-тестирование - неотъемлемая часть разработки качественного программного обеспечения. Особенно это актуально при работе с бизнес-логикой, где важно изолировать тестируемый компонент от его зависимостей (например, базы данных, внешних API и т.д.). 

В Go для этой цели часто используют моки - заглушки, имитирующие поведение зависимостей. Когда проект построен по принципам слоёной архитектуры и инверсии зависимостей (Dependency Inversion Principle из SOLID), интерфейсы уже есть «из коробки», и создание моков становится естественным шагом. 

В этой статье мы рассмотрим, как сделать работу с моками удобнее, используя инструмент [mockery](https://vektra.github.io/mockery/latest/) и небольшую вспомогательную структуру для организации тестов. 

> В примерах используется `mockery` версии 2.x. Начиная с версии 3, синтаксис `go:generate` немного изменился - об этом ниже.
{ .prompt-info }

---

## Пример бизнес-логики

Рассмотрим упрощённый сервис регистрации пользователей:

```go {file="service.go"}

// UsersRepo интерфейс репозитория пользователей
type UsersRepo interface {
	CreateUser(ctx context.Context, username string) error
}

// UsersService сервис работы с пользователями
type UsersService struct {
	repo UsersRepo
}

// NewUsersService конструктор сервиса
func NewUsersService(repo UsersRepo) *UsersService {
	return &UsersService{
		repo: repo,
	}
}

// RegisterUser регистрация пользователя
func (s *UsersService) RegisterUser(ctx context.Context, username string) error {
	if err := validateUsername(username); err != nil {
		return fmt.Errorf("validateUsername: %w", err)
	}

	if err := s.repo.CreateUser(ctx, username); err != nil {
		return fmt.Errorf("repo.CreateUser: %w", err)
	}

	return nil
}

func validateUsername(username string) error {
	if len(username) < 3 {
		return errors.New("username must be at least 3 characters long")
	}

	return nil
}

```

> В примере намеренно упрощена реализация. В реальном проекте стоит вынести ошибки в отдельный пакет и добавить проверку на дубликаты. Однако для демонстрации принципа этого достаточно.
{ .prompt-info }

---

## Генерация моков с помощью mockery

Для автоматической генерации моков используем `mockery` . Для версий до `3.0` достаточно добавить директиву `go:generate`:
```go {file="service.go"}
//go:generate mockery --case=snake --with-expecter --name=UsersRepo
```
После запуска `go generate ./...` будет создан файл с моком, например, в папке mocks/.

> Начиная с `mockery v3`, рекомендуется использовать конфигурационный файл `.mockery.yaml` и вызывать `mockery` напрямую, а не через `go:generate`. Подробнее [в официальной документации](https://vektra.github.io/mockery/latest).
{ .prompt-info }

Альтернативные инструменты, такие как `gomock` или `minimock`, предлагают схожий подход - генерация моков на основе интерфейсов.

---

## Организация тестов через вспомогательный контейнер 

Чтобы избежать дублирования кода инициализации моков в каждом тесте, можно завести небольшую вспомогательную структуру: 

```go {file="service_test.go"}
type testMocks struct {
	repo         *mocks.UsersRepo
	usersService *UsersService
}

func newTestMocks(t *testing.T) *testMocks {
	t.Helper()
	repo := mocks.NewUsersRepo(t)

	return &testMocks{
		repo:         repo,
		usersService: NewUsersService(repo),
	}
}

```

Такой подход особенно удобен, когда зависимостей становится больше: достаточно обновить `testMocks` и `newTestMocks`, и все тесты получат актуальные заглушки.

---

## Написание чистых и читаемых тестов

Теперь тесты становятся лаконичными и сфокусированными на проверяемом поведении:

```go {file="service_test.go"}

func Test_RegisterUser_ExpectOk(t *testing.T) {
	m := newTestMocks(t)

	username := "test_username"
	
	m.repo.EXPECT().
		CreateUser(mock.AnythingOfType("context.backgroundCtx"), username).
		Return(nil).
		Once()

	err := m.usersService.RegisterUser(context.Background(), username)
	require.NoError(t, err)
}

func Test_RegisterUser_InvalidUsername_ExpectErr(t *testing.T) {
	m := newTestMocks(t)

	username := "te" // слишком короткое имя

	// Репозиторий не должен быть вызван - валидация сработает раньше
	err := m.usersService.RegisterUser(context.Background(), username)
	require.EqualError(t, err, "validateUsername: username must be at least 3 characters long")
}

func Test_RegisterUser_RepoError_ExpectErr(t *testing.T) {
	m := newTestMocks(t)

	username := "test_username"

	m.repo.EXPECT().
		CreateUser(mock.AnythingOfType("context.backgroundCtx"), username).
		Return(errors.New("database timeout")).
		Once()

	err := m.usersService.RegisterUser(context.Background(), username)
	require.EqualError(t, err, "repo.CreateUser: database timeout")
}

```

---

## Заключение 

Использование вспомогательных структур вроде `testMocks` и генераторов моков (например, `mockery`) позволяет писать unit-тесты в Go удобнее. Такой подход масштабируется по мере роста проекта и делает тесты чище, читаемее и проще в поддержке. 

Если ты только начинаешь писать тесты - не бойся начинать с простого. Даже базовая изоляция зависимостей через интерфейсы и моки уже даёт огромную пользу. 

--- 

📎 **Источники**:
  - [Mockery Documentation](https://vektra.github.io/mockery/latest/)
  - [Go Testing Package](https://pkg.go.dev/testing)
  - [Testify](https://github.com/stretchr/testify) 
  - [Go Blog: Advanced Testing with Go](https://go.dev/blog/examples)
