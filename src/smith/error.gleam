import gleam/int
import gleam/string
import smith/types.{type AgentError, type RecoveryStrategy, type Status}

// Error severity levels
pub type ErrorSeverity {
  CriticalError
  HighError
  MediumError
  LowError
}

/// ========================================================================
/// Agent Error
/// ========================================================================
pub fn format_status(status: Status) -> String {
  case status {
    types.Available -> "Available"
    types.Busy(_) -> "Busy"
    types.Paused(_) -> "Paused"
    types.Maintenance -> "Maintenance"
    types.ShuttingDown -> "Shutting down"
    types.AgentError(_) -> "Error"
  }
}

pub fn format_recovery_strategy(strategy: RecoveryStrategy) -> String {
  case strategy {
    types.RetryWithBackoff(_, _) -> "Retry with backoff"
    types.DelegateToFallback(_) -> "Delegate to fallback"
    types.RestartClean -> "Restart clean"
    types.NotifyAndWait -> "Notify and wait"
  }
}

// Error handling utilities
pub fn format_error(error: AgentError) -> String {
  case error {
    types.ToolExecutionError(reason) ->
      string.concat(["Tool execution failed: ", reason])

    types.ToolNotFoundError(decode_error) ->
      string.concat(["Invalid tool call: ", string.inspect(decode_error)])

    types.TaskExecutionError(task_id, reason) ->
      string.concat(["Task execution failed for ", task_id, ": ", reason])

    types.TaskValidationError(task_id, reason) ->
      string.concat(["Task validation failed for ", task_id, ": ", reason])

    types.TaskTimeoutError(task_id, timeout) ->
      string.concat([
        "Task ",
        task_id,
        " timed out after ",
        int.to_string(timeout),
        "ms",
      ])

    types.TaskDependencyError(task_id, dependency_id) ->
      string.concat([
        "Task ",
        task_id,
        " failed due to dependency ",
        dependency_id,
      ])

    types.StateError(reason) -> string.concat(["State error: ", reason])

    types.InvalidStateTransition(from, to) ->
      string.concat([
        "Invalid state transition from ",
        format_status(from),
        " to ",
        format_status(to),
      ])

    types.ResourceExhausted(resource) ->
      string.concat(["Resource exhausted: ", resource])

    types.MemoryLimitExceeded(current, limit) ->
      string.concat([
        "Memory limit exceeded: ",
        int.to_string(current),
        "/",
        int.to_string(limit),
        " bytes",
      ])

    types.ConcurrencyLimitExceeded(current, limit) ->
      string.concat([
        "Concurrency limit exceeded: ",
        int.to_string(current),
        "/",
        int.to_string(limit),
        " tasks",
      ])

    types.CommunicationError(target, reason) ->
      string.concat(["Communication failed with agent ", target, ": ", reason])

    types.MessageDeliveryError(message_id, reason) ->
      string.concat(["Failed to deliver message ", message_id, ": ", reason])

    types.SupervisorError(reason) ->
      string.concat(["Supervisor error: ", reason])

    types.InitializationError(reason) ->
      string.concat(["Initialization failed: ", reason])

    types.ShutdownError(reason) -> string.concat(["Shutdown failed: ", reason])

    types.RecoveryStrategyError(strategy, reason) ->
      string.concat([
        "Recovery strategy ",
        format_recovery_strategy(strategy),
        " failed: ",
        reason,
      ])

    types.RetryLimitExceeded(attempts, max_retries) ->
      string.concat([
        "Retry limit exceeded: ",
        int.to_string(attempts),
        "/",
        int.to_string(max_retries),
        " attempts",
      ])

    types.CustomError(code, reason, _) ->
      string.concat(["Error ", code, ": ", reason])
  }
}

pub fn get_error_severity(error: AgentError) -> ErrorSeverity {
  case error {
    types.InitializationError(_) -> CriticalError
    types.SupervisorError(_) -> CriticalError
    types.MemoryLimitExceeded(_, _) -> CriticalError
    types.ConcurrencyLimitExceeded(_, _) -> CriticalError

    types.TaskExecutionError(_, _) -> HighError
    types.CommunicationError(_, _) -> HighError
    types.StateError(_) -> HighError
    types.InvalidStateTransition(_, _) -> HighError
    types.RecoveryStrategyError(_, _) -> HighError
    types.ShutdownError(_) -> HighError

    types.ToolExecutionError(_) -> MediumError
    types.TaskTimeoutError(_, _) -> MediumError
    types.ResourceExhausted(_) -> MediumError
    types.MessageDeliveryError(_, _) -> MediumError
    types.RetryLimitExceeded(_, _) -> MediumError

    types.TaskValidationError(_, _) -> LowError
    types.ToolNotFoundError(_) -> LowError
    types.CustomError(_, _, _) -> LowError
    types.TaskDependencyError(_, _) -> LowError
  }
}
