import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option}

// Type definitions for the core components

pub type AgentId =
  String

pub type ToolId =
  String

pub type StateUpdater(st) =
  fn(AgentState(st)) -> AgentState(st)

// Custom types for agent messages
pub type AgentMessage(st) {
  TaskAssignment(task: Task)
  ToolRequest(tool: ToolId, params: Dynamic)
  StateUpdate(state: AgentState(st))
  CompletionNotification(result: TaskResult)
}

pub type MemoryEntry {
  MemoryEntry(key: String, value: Dynamic)
}

// Agent state definition
pub type AgentState(st) {
  AgentState(
    id: AgentId,
    status: Status,
    current_task: Option(Task),
    memory: List(MemoryEntry),
    state: st,
    tools: List(Tool),
    recovery_strategy: RecoveryStrategy,
    error_count: Int,
  )
}

// Agent status
pub type Status {
  Available
  Busy(task_count: Int)
  Paused(reason: String)
  Maintenance
  ShuttingDown
  AgentError(error: AgentError)
}

pub type Task {
  Task(
    id: String,
    name: String,
    description: String,
    priority: TaskPriority,
    status: TaskStatus,
    created_at: Int,
    deadline: Option(Int),
    dependencies: List(String),
    // List of task IDs this task depends on
    sender: AgentId,
    // Agent that created the task
    target: AgentId,
    // Agent meant to execute the task
    context: Dynamic,
    // Task-specific data
    required_tools: List(ToolId),
  )
}

// Task related types
pub type TaskPriority {
  Low
  Medium
  High
  Critical
}

pub type TaskStatus {
  Pending
  InProgress(started_at: Int)
  Completed(completed_at: Int)
  Failed(error: AgentError)
  Cancelled(reason: String)
}

pub type TaskResult {
  TaskResult(
    task_id: String,
    status: TaskStatus,
    output: Dynamic,
    execution_time: Int,
    tools_used: List(ToolId),
    error: Option(AgentError),
    metadata: Dict(String, Dynamic),
  )
}

pub type RecoveryStrategy {
  RetryWithBackoff(max_retries: Int, base_delay: Int)
  DelegateToFallback(fallback_agent: AgentId)
  RestartClean
  NotifyAndWait
}

// Tool definition
pub type Tool {
  Tool(
    id: ToolId,
    name: String,
    description: String,
    handler: fn(Dynamic) -> Result(Dynamic, String),
  )
}

pub type AgentError {
  // Tool related errors
  ToolExecutionError(tool_id: ToolId, reason: String)
  ToolNotFoundError(tool_id: ToolId)
  ToolInitializationError(tool_id: ToolId, reason: String)

  // Task related errors
  TaskExecutionError(task_id: String, reason: String)
  TaskValidationError(task_id: String, reason: String)
  TaskTimeoutError(task_id: String, timeout: Int)
  TaskDependencyError(task_id: String, dependency_id: String)

  // State related errors
  StateError(reason: String)
  InvalidStateTransition(from: Status, to: Status)

  // Resource errors
  ResourceExhausted(resource: String)
  MemoryLimitExceeded(current: Int, limit: Int)
  ConcurrencyLimitExceeded(current: Int, limit: Int)

  // Communication errors
  CommunicationError(target: AgentId, reason: String)
  MessageDeliveryError(message_id: String, reason: String)

  // System errors
  SupervisorError(reason: String)
  InitializationError(reason: String)
  ShutdownError(reason: String)

  // Recovery errors
  RecoveryStrategyError(strategy: RecoveryStrategy, reason: String)
  RetryLimitExceeded(attempts: Int, max_retries: Int)

  // Custom errors
  CustomError(code: String, reason: String, metadata: Dict(String, Dynamic))
}
