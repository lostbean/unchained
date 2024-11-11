import agent
import gleam/option.{Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn chain_test() {
  let tool =
    agent.Tool(
      name: "format",
      description: "Format the translation",
      function: fn(x) { Ok(string.uppercase(x)) },
    )
  let chain =
    agent.new()
    |> agent.add_prompt_template(
      "Translate this to {{ language }}: {{ input }}
    Just reply with the translation, do not include any explanation. Make sure to format the answer first.

    Here is the list of tools available to use:
    {{#each tools}}
      Function Name: {{name}}
      Function Description: {{description}}
      ---
    {{/each}}

    To use too call it with:
    Tool Selected: <tool name>
    ",
      ["language", "input"],
      [agent.ToolSelector(fn(_) { Some("") }, tool)],
    )
    |> should.be_ok()
    |> agent.set_variable("language", "French")
    |> agent.set_variable("input", "lost bread")
    |> agent.add_llm("Translate:")
    |> agent.add_tool(tool)

  let config =
    agent.LLMConfig(
      base_url: "localhost:11434",
      model: "llama3.2:3b",
      temperature: 0.0,
    )
  // Run the chain
  agent.run(config, chain, "Hello world")
  |> should.be_ok()
  |> should.equal("PAIN    PERDU")
}
