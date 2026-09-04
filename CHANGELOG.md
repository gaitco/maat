## 0.1.2

- Add `api:openapi`, which exports the registered routes as an OpenAPI 3.1 document.
- Add `api:client`, which generates a typed Dart client from the same contract.
- Describe routes with `RouteContract` and `ApiSchema`, derived from the validation rules a route already declares.

## 0.1.1

- Add Pusher-compatible broadcasting, channel authorization, fakes, and console commands.
- Reject ports owned by unrelated processes while preserving Maat worker sharing.

## 0.1.0

- Initial release of the Maat HTTP framework.
- Includes routing, middleware, validation, authentication, console commands, events, testing utilities, and production server support.
