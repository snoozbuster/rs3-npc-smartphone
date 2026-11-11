local bind = require("lib/bind")
local element = require("lib/element")

describe("bind", function()
  local function fakeHost()
    local mounts = {}
    local updates = {}
    local destroys = 0

    local host = {
      mount = function(parent, vnode)
        mounts[#mounts + 1] = { parent = parent, vnode = vnode }
        return {
          update = function(next)
            updates[#updates + 1] = next
          end,
          destroy = function()
            destroys = destroys + 1
          end,
        }
      end,
    }

    return host, {
      mounts = mounts,
      updates = updates,
      getDestroys = function()
        return destroys
      end,
    }
  end

  local function fakeNotifier()
    local listeners = {}
    return {
      listeners = listeners,
      subscribe = function(fn)
        listeners[#listeners + 1] = fn
        return function()
          for i = 1, #listeners do
            if listeners[i] == fn then
              table.remove(listeners, i)
              return
            end
          end
        end
      end,
      notify = function()
        local snapshot = {}
        for i = 1, #listeners do
          snapshot[i] = listeners[i]
        end
        for i = 1, #snapshot do
          snapshot[i]()
        end
      end,
    }
  end

  it("mount paints via render(parent) and re-renders on subscribe notify", function()
    local host, hostLog = fakeHost()
    local notifier = fakeNotifier()
    local paints = {}

    ---@diagnostic disable-next-line: missing-fields
    local parent = { width = 10, height = 20 }

    local bound = bind.new({
      host = host,
      subscribe = notifier.subscribe,
      render = function(p)
        paints[#paints + 1] = p
        return element.h("box", { width = p.width, height = p.height })
      end,
    })

    local instance = bound.mount(parent)
    assert.are.equal(1, #hostLog.mounts)
    assert.are.equal(parent, hostLog.mounts[1].parent)
    assert.are.equal(parent, paints[1])
    assert.are.equal(1, #notifier.listeners)

    notifier.notify()
    assert.are.equal(1, #hostLog.updates)
    assert.are.equal(2, #paints)
    assert.are.equal(parent, paints[2])

    instance.unmount()
    assert.are.equal(1, hostLog.getDestroys())
    assert.are.equal(0, #notifier.listeners)

    notifier.notify()
    assert.are.equal(1, #hostLog.updates)
  end)

  it("one-shot mount works without subscribe", function()
    local host, hostLog = fakeHost()

    ---@diagnostic disable-next-line: missing-fields
    local parent = { width = 3, height = 4 }

    local bound = bind.new({
      host = host,
      render = function(p)
        return element.h("box", { width = p.width, height = p.height })
      end,
    })

    local instance = bound.mount(parent)
    assert.are.equal(1, #hostLog.mounts)
    instance.unmount()
    assert.are.equal(1, hostLog.getDestroys())
  end)

  it("update remounts under a new parent without resubscribing", function()
    local host, hostLog = fakeHost()
    local notifier = fakeNotifier()

    ---@diagnostic disable-next-line: missing-fields
    local parentA = { width = 1, height = 1 }
    ---@diagnostic disable-next-line: missing-fields
    local parentB = { width = 2, height = 2 }

    local bound = bind.new({
      host = host,
      subscribe = notifier.subscribe,
      render = function(p)
        return element.h("box", { width = p.width, height = p.height })
      end,
    })

    local instance = bound.mount(parentA)
    assert.are.equal(1, #notifier.listeners)
    assert.are.equal(1, #hostLog.mounts)

    instance.update(parentB)
    assert.are.equal(1, hostLog.getDestroys())
    assert.are.equal(2, #hostLog.mounts)
    assert.are.equal(parentB, hostLog.mounts[2].parent)
    assert.are.equal(1, #notifier.listeners)

    notifier.notify()
    assert.are.equal(1, #hostLog.updates)
    assert.are.equal(2, hostLog.updates[1].props.width)

    instance.unmount()
    assert.are.equal(2, hostLog.getDestroys())
    assert.are.equal(0, #notifier.listeners)
  end)

  it("allows two instances from one definition", function()
    local host, hostLog = fakeHost()
    local notifier = fakeNotifier()

    ---@diagnostic disable-next-line: missing-fields
    local hub = { width = 100, height = 100 }
    ---@diagnostic disable-next-line: missing-fields
    local ribbon = { width = 200, height = 200 }

    local bound = bind.new({
      host = host,
      subscribe = notifier.subscribe,
      render = function(p)
        return element.h("box", { width = p.width, height = p.height })
      end,
    })

    local a = bound.mount(hub)
    local b = bound.mount(ribbon)
    assert.are.equal(2, #hostLog.mounts)
    assert.are.equal(hub, hostLog.mounts[1].parent)
    assert.are.equal(ribbon, hostLog.mounts[2].parent)
    assert.are.equal(2, #notifier.listeners)

    a.unmount()
    b.unmount()
    assert.are.equal(2, hostLog.getDestroys())
    assert.are.equal(0, #notifier.listeners)
  end)
end)
