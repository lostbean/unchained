import agent
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

  let config =
    agent.LLMConfig(
      host: "localhost:11434",
      model: "llama3.2:3b",
      temperature: 0.0,
    )

  let chain =
    agent.new()
    |> agent.add_prompt_template(
      "Translate this to {{ language }}: {{ input }}",
      ["language", "input"],
      [],
    )
    |> should.be_ok()
    |> agent.set_variable("language", "French")
    |> agent.set_variable("input", "lost bread")
    |> agent.add_llm(config)
    |> agent.add_tool(tool)

  // Run the chain
  agent.run_with(chain, "Hello world", fn(input, _cfg) {
    input |> should.equal("Translate this to French: lost bread")
    Ok(agent.Response("pain perdu"))
  })
  |> should.be_ok()
  |> should.equal("PAIN PERDU")
}
