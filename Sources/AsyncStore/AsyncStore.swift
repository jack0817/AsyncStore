import Foundation

final class AsyncStore<State, Environment>: ObservableObject {
    private var _state: State
    private let _env: Environment
    private let _mapError: (Error) -> Effect
    private var cancellables: [AnyHashable: () -> Void] = [:]
    
    init(state: State, env: Environment, mapError: @escaping (Error) -> Effect) {
        self._state = state
        self._env = env
        self._mapError = mapError
    }
    
    public func receive(_ effect: Effect) {
        Task { await reduce(effect) }
    }
}

extension AsyncStore {
    private func reduce(_ effect: Effect) async {
        switch effect {
        case .none:
            break
        case .set(let setter):
            await setOnMain(setter)
        case .task(let operation, let id):
            cancel(id)
            let task = Task {
                let effect = await execute(operation)
                await reduce(effect)
            }
            store(cancel: task.cancel, for: id)
            await task.value
        case .sleep(let time):
            do {
                try await Task.trySleep(for: time)
            } catch let error {
                let effect = _mapError(error)
                await reduce(effect)
            }
        case .merge(let effects):
            let mergeStream = AsyncStream<Void> { cont in
                effects.forEach { effect in
                    Task {
                        await reduce(effect)
                        cont.yield(())
                    }
                }
            }
            
            var mergeCount = 0
            for await _ in mergeStream {
                mergeCount += 1
                guard mergeCount < effects.count else { break }
            }
        case .concatenate(let effects):
            for effect in effects {
                await reduce(effect)
            }
        }
    }
}

extension AsyncStore {
    private func cancel(_ id: AnyHashable?) {
        guard let id = id else { return }
        cancellables[id]?()
    }
    
    private func execute(_ operation: () async throws -> Effect) async -> Effect {
        do {
            return try await operation()
        } catch let error {
            return _mapError(error)
        }
    }
    
    private func store(cancel: @escaping () -> Void, for id: AnyHashable?) {
        guard let id = id else { return }
        cancellables[id] = cancel
    }
    
    @MainActor private func setOnMain(_ setter: @escaping (inout State) -> Void) {
        objectWillChange.send()
        setter(&_state)
    }
}
