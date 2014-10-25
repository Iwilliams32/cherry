# spop music handling
spop = q: [], cache: []

# from wit output to hue input
wit_to_hue = (entities) ->
  opts = {}
  if x = parseInt(entities.color?[0].value, 10)
    opts.hue = x
  if x = entities.alert?[0].value
    opts.alert = x
  if x = entities.effect?[0].value
    opts.effect = x
  if x = entities.light?[0].value
    opts.light = x
  if x = entities.on_off?[0].value
    opts.on = x == "on"

  return opts

module.exports = (cherry) ->
  p = cherry.plugins()

  intents =
    bot_hello: -> p.tts "Good day to you!"
    bot_name:  -> p.tts "My name is Samantha."
    bot_sport: -> p.tts "My favorite sport is volleyball. I quite like soccer too."
    bot_maker: -> p.tts "I have been made in Palo Alto, by the Wit team"
    party: ->
      p.spop 'uplay spotify:track:1CNJyTUh56oj3OCZOZ5way'
      setTimeout (-> p.spop "seek", seconds: 58200), 75
      p.hue(on: true, alert: 'lselect', effect: 'colorloop')
      p.disco true
    disco_ball: (entities) ->
      p.disco entities?.on_off?[0].value == 'on'
    lights: (entities) ->
      # (put! ->ec {:to "chat" :body (str "Hue: " (pr-str opts))}))
      p.hue(wit_to_hue(entities))
    music_play: (entities) ->
      # does user want something specific?
      if music_item = entities?.music?[0].value
        spop.q.push (r) ->
          if (dym = r.did_you_mean)
            cherry.produce to: 'chat', body: "Did you mean #{dym}?"

          if (x = (r.albums?[0] || r.tracks?[0])) && (uri = x.uri)
            p.spop("uplay #{uri}")
          else
            cherry.produce(to: 'chat', body: 'Did not find anything matching: ' + music_item)
            console.log('[spop/play] did not find uri', Object.keys(r))
        escaped = music_item.replace('"', '')
        p.spop("search \"#{escaped}\"")
      else
        p.spop('play')
    video_play: (entities) -> p.youtube(entities)
    music_stop: -> p.spop('stop')
    music_pause: -> p.spop 'toggle'
    music_resume: -> p.spop 'resume'
    music_next: -> p.spop('next')
    music_previous: -> p.spop('prev')
    music_status: -> p.spop('status')
    music_qclear: -> p.spop "qclear"
    music_qlist: ->
      spop.q.push (r) ->
        if !(r && r.tracks)
          console.log '[spop/qls] ERROR: spop returned unexpected response', r

        if !r.tracks.length
          console.log '[spop/qls] nothing in queue'
          cherry.produce(to: 'chat', body: "There's nothing in the queue")
          return

        out = ''
        xs = r.tracks

        if (xs.length == 1)
          out += "There is one item in the queue:\n"
        else
          out += "There are " + xs.length + " items in the queue:\n"

        out += xs.map((x, i) ->
          return '' + (i+1) + '. ' + x.title + " by " + x.artist + " (" + x.album + ")"
        ).join('\n')

        console.log('[spop/qls]' + out)
        cherry.produce(to: 'chat', body: out)

      p.spop "qls"
    music_search: (entities) ->
      item = entities.music?[0].value
      if item
        spop.q.push (x) ->
          if x.query && (x.total_tracks == 0 || x.total_tracks)
            process = (label, items) ->
              items.slice(0, 5).map (x) ->
                x.pretty = if x.title && x.artist
                  "#{label} - #{x.title} by #{x.artist}"
                else if x.name
                  "#{label} - #{x.name}"
                else
                  "#{label} - unknown #{x.uri}"
                x

            spop.cache = process('album', x.albums)
              .concat(process('song', x.tracks))
              .concat(process('playlist', x.playlists))

            msg = if (dym = x.did_you_mean)
              "Did you mean #{dym}? Anyway, here's what I got:\n"
            else
              "Found those:\n"

            msg += spop.cache.map((x, i) ->
              "#{i+1}. #{x.pretty}"
            ).join('\n')

            cherry.produce to: 'chat', body: msg
          else
            console.log('[spop/search] did not get any result', x)

        p.spop 'search "' + item + '"'
      else
        console.log('[spop/search] not an item', item)
    music_goto: (entities) ->
      n = parseInt(entities.number?[0].value || -1, 10)
      if n > 0
        p.spop "goto " + n
      else
        console.log('[spop/goto] not a number', n)
    music_enqueue_from_search: (entities) ->
      n = parseInt(entities.number?[0].value || -1, 10)
      if n > 0 && (uri = spop.cache[n-1]?.uri)
        spop.q.push (r) ->
          if tot = r.total_tracks
            msg = "I added #{tot} items to the queue."
            cherry.produce(to: 'chat', body: msg)
          else
            console.log('[spop/enqueue] unexpected response', r)
        p.spop "uadd " + uri
      else
        console.log('[spop/enqueue] not in queue', n)

  cherry.handle
    chat: (x) ->
      p.wit(text: x) # send all chats to wit
    queue: (x) ->
      return if !x.outcomes || !x.outcomes.length
      outcome = x.outcomes[0]
      intent = outcome.intent
      entities = outcome.entities
      if f = intents[intent]
        f(entities || {})
      else
        console.log '[wit] unknown intent', intent
    pin: (x) ->
      if x.state == 'low'
        p.wit(mic: 'stop')
      else
        p.wit(mic: 'start')
    spop: (x) ->
      if (f = spop.q.shift())
        f(x)
      else if x.status
        out = "[spop] #{x.status}, total tracks=#{x.total_tracks}"
        if x.current_track
          out += " song=#{x.title} artist=#{x.artist} album=#{x.album}"
        cherry.produce(to: 'chat', body: out)
        console.log '[cambridge/spop] ' + out

      # p.hipchat(JSON.stringify(x))
    myo: (x) ->
      if x.type == 'pose'
        pose = x.pose
        if pose == 'wave_in'
          p.hue(on: true, lights: [1, 2])
        else if pose == 'wave_out'
          p.hue(on: false, lights: [1, 2])
    wit: (x) ->
      return if !x.outcomes || !x.outcomes.length
      outcome = x.outcomes[0]
      intent = outcome.intent
      entities = outcome.entities
      switch intent
        when 'hto_queue_pop' then p.queue(pop: 'foo') unless x.cherry.msg.from
        when 'hto_queue_toggle' then p.queue(toggle: 'bar') unless x.cherry.msg.from
        when 'hto_queue_delay'
          s = entities.duration.reduce (sum, curr) ->
                sum += curr.value
              , 0
          if !x.cherry.from
            p.queue(delay: s)
        else p.queue(push: x)
    dockerhub: (x) ->
      push_data  = x.push_data
      repo       = x.repository
      owner      = repo?.owner
      name       = repo?.name
      namespace  = repo?.namespace
      repo_name  = repo?.repo_name
      repo_url   = repo?.repo_url
      images     = push_data?.images
      pusher     = push_data?.pusher

      body = "[dockerhub] #{pusher} pushed to #{repo_name}"
      if images?.length
        body += " (#{images?.length || 0} images: #{images?.join(", ")})"

      cherry.produce
        to: 'chat'
        body: body

      ###
      {
         "push_data":{
            "pushed_at":1385141110,
            "images":[
               "imagehash1",
               "imagehash2",
               "imagehash3"
            ],
            "pusher":"username"
         },
         "repository":{
            "status":"Active",
            "description":"my docker repo that does cool things",
            "is_trusted":false,
            "full_description":"This is my full description",
            "repo_url":"https://registry.hub.docker.com/u/username/reponame/",
            "owner":"username",
            "is_official":false,
            "is_private":false,
            "name":"reponame",
            "namespace":"username",
            "star_count":1,
            "comment_count":1,
            "date_created":1370174400,
            "dockerfile":"my full dockerfile is listed here",
            "repo_name":"username/reponame"
         }
      }
      ###
