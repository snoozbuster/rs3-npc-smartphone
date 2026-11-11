local npc_contact_subject = require("npc_contact_subject")

describe("npc_contact_subject.isNpcContactSubject", function()
  it("matches the NPC Contact subject", function()
    assert.is_true(npc_contact_subject.isNpcContactSubject("NPC Contact"))
  end)

  it("matches coloured / mixed-case subjects", function()
    assert.is_true(npc_contact_subject.isNpcContactSubject("<col=ffffff>Npc Contact</col>"))
  end)

  it("rejects unrelated subjects", function()
    assert.is_false(npc_contact_subject.isNpcContactSubject("Banker"))
  end)
end)
