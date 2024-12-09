import gleam/erlang/process
import gleam/int
import gleam/option.{None, Some}

import smith/error
import smith/task
import smith/types.{type AgentError, type AgentId, type AgentState, type Status}

// Status management functions
pub fn update_agent_status(
  state: AgentState(state, tool),
  new_status: Status,
) -> AgentState(state, tool) {
  types.AgentState(..state, status: new_status)
}

pub fn is_available(state: AgentState(state, tool)) -> Bool {
  case state.status {
    types.Available -> True
    _ -> False
  }
}

pub fn is_busy(state: AgentState(state, tool)) -> Bool {
  case state.status {
    types.Busy(_) -> True
    _ -> False
  }
}

pub fn handle_error_with_recovery(
  state: AgentState(state, tool),
  err: AgentError,
) -> AgentState(state, tool) {
  // Log the error
  // log_error(state.id, error)

  // Update error metrics
  // let state = update_error_metrics(state, error)

  // Check if we should attempt recovery based on severity
  case error.get_error_severity(err) {
    error.CriticalError -> {
      notify_supervisor(state.id, err)
      types.AgentState(..state, status: types.AgentError(err))
    }

    error.HighError | error.MediumError -> {
      attempt_recovery(state, err)
    }

    error.LowError -> {
      // For low severity, just log and continue
      state
    }
  }
}

pub fn notify_supervisor(_agent_id: AgentId, _error: AgentError) {
  // supervisor.notify(agent_id, error)
  todo
}

pub fn calculate_backoff_delay(base_delay: Int, error_count: Int) -> Int {
  // TODO: review this
  base_delay * { int.bitwise_shift_left(error_count, 2) }
}

pub fn retry_failed_operation(
  state: AgentState(state, tool),
  error: AgentError,
) -> AgentState(state, tool) {
  let new_state = types.AgentState(..state, error_count: state.error_count + 1)
  case state.current_task {
    Some(task) -> {
      let task_result = task.create_error_result(task, error)
      let new_state = task.complete_task(new_state, task_result)
      new_state
    }
    None -> new_state
  }
}

pub fn delegate_to_fallback(
  _state: AgentState(state, tool),
  _fallback_agent: AgentId,
  _error: AgentError,
) -> AgentState(state, tool) {
  // supervisor.delegate(state.id, fallback_agent, error)
  todo
}

pub fn pause_agent(
  state: AgentState(state, tool),
  reason: String,
) -> AgentState(state, tool) {
  types.AgentState(..state, status: types.Paused(reason), current_task: None)
}

fn attempt_recovery(
  state: AgentState(state, tool),
  error: AgentError,
) -> AgentState(state, tool) {
  case state.recovery_strategy {
    types.RetryWithBackoff(max_retries, base_delay) -> {
      case state.error_count <= max_retries {
        True -> {
          let delay = calculate_backoff_delay(base_delay, state.error_count)
          process.sleep(delay)
          retry_failed_operation(state, error)
        }
        False ->
          types.AgentState(
            ..state,
            status: types.AgentError(types.RetryLimitExceeded(
              state.error_count,
              max_retries,
            )),
          )
      }
    }

    types.DelegateToFallback(fallback_agent) -> {
      delegate_to_fallback(state, fallback_agent, error)
    }

    types.RestartClean -> {
      // try new_state = cleanup_state(state)
      // try new_state = reinitialize_agent(new_state)
      // Ok(new_state)
      todo
    }

    types.NotifyAndWait -> {
      notify_supervisor(state.id, error)
      pause_agent(state, "Waiting for manual intervention")
    }
  }
}
