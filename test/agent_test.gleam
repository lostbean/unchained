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
      "Translate this to {{ language }}: {{ input }}",
      ["language", "input"],
      [],
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
  agent.run_with(config, chain, "Hello world", fn(input, _cfg) {
    input |> should.equal("Translate:\nTranslate this to French: lost bread")
    Ok(agent.Response("pain perdu"))
  })
  |> should.be_ok()
  |> should.equal("PAIN PERDU")
}
