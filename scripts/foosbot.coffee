# Description:
#   An LCB bot that arranges foosball games
#
# Commands:
#   foosbot Games - List currently scheduled games
#   foosbot Start game - Start a new game, always added to the end of the queue
#   foosbot Find people - Ask for people to play in the next game
#   foosbot I'm in | Join game - Claim a spot in the next game
#   foosbot Add <player_name> - Add a player that may or may not be on LCB to the next game
#   foosbot Kick <player_name> - Kick a player from the next game
#   foosbot Abandon game - Free up your spot in the next game
#   foosbot Cancel game - Cancel the next game
#   foosbot Find people for game <n> - Ask for people to play in the nth game
#   foosbot Join game <n> - Claim a spot in the nth game
#   foosbot Add <player_name> to game <n> - Add a player that may or may not be on LCB to the nth game
#   foosbot Kick <player_name> from game <n> - Kick a player from the nth game
#   foosbot Abandon game <n> - Free up your spot in the nth game
#   foosbot Cancel game <n> - Cancel the nth game
#   foosbot Finish game: <team1_p1> and <team1_p2> vs. <team2_p1> and <team2_p2>, final score <team1_score>-<team2_score> - Finish the next game and record the results
#
# Author:
#   MartinPetkov

fs = require 'fs'

gamesFile = 'games.json'
finishedGamesFile = 'finishedgames.json'

games = JSON.parse((fs.readFileSync gamesFile, 'utf8').toString().trim())
finishedGames = JSON.parse((fs.readFileSync finishedGamesFile, 'utf8').toString().trim())


saveGames = () ->
  fs.writeFileSync(gamesFile, JSON.stringify(games))

saveFinishedGames = () ->
  fs.writeFileSync(finishedGamesFile, JSON.stringify(finishedGames))


isUndefined = (myvar) ->
  return typeof myvar == 'undefined'


gamesRespond = (res) ->
  # TODO: List the games, in groups of 4, with the indices
  if games.length <= 0
    res.send "No games started"
    return

  responseLines = []
  for game, index in games
    players = game.join(', ')
    responseLines.push "Game #{index}: #{players}"

  res.send responseLines.join('\n')


startGameRespond = (res) ->
  # TODO: Create a new group of four, at the end of the games array
  captain = res.message.user.name
  games.push [captain, '_', '_', '_']
  saveGames()

  res.send "New game started"
  gamesRespond(res)


isInvalidIndex = (gameIndex) ->
  return isNaN(gameIndex) || gameIndex < 0 || gameIndex >= games.length


findPeopleForGameRespond = (res, n) ->
    n = if isUndefined(n) then parseInt(res.match[1].trim(), 10) else n
    if isInvalidIndex(n)
        res.send "Invalid game index #{n}"
        return

    gameStr = if n == 0 then "Next game" else "Game #{n}"

    game = games[n]
    currentPlayers = (player for player in game when player != "_")
    spotsLeft = 4 - currentPlayers.length
    if spotsLeft <= 0
        res.send "No spots left in #{gameStr}"
        return

    # Ask @all who's up for a game, and announce who's currently part of the nth game
    currentPlayers = currentPlayers.join(', ')

    res.send "@all Who's up for a game? #{gameStr} has #{spotsLeft} spots, current players are #{currentPlayers}"


joinGameRespond = (res, n, playerName) ->
    newPlayer = if isUndefined(playerName) then res.message.user.name else playerName
    n = if isUndefined(n) then parseInt(res.match[1].trim(), 10) else n
    any = if !any then false else true
    if isInvalidIndex(n)
        res.send "Invalid game index #{n}"
        return

    gameStr = if n == 0 then "Next game" else "Game #{n}"

    game = games[n]
    if game.indexOf(newPlayer) >= 0
        res.send "You're already part of that game!"
        return

    # Add yourself to the nth game
    for player, index in game
        if player == '_'
            game[index] = newPlayer
            res.send "#{newPlayer} joined #{gameStr}!"
            if game.indexOf('_') < 0
                gamePlayers = ["@#{player}" for player in game].join(', ')
                res.send "#{gameStr} is ready to go! Players: #{gamePlayers}"

            saveGames()
            gamesRespond(res)

            return

    # Cannot join if full
    res.send "No spots #{gameStr}"


abandonGameRespond = (res, n, playerName) ->
    senderPlayer = if isUndefined(playerName) then res.message.user.name else playerName
    n = if isUndefined(n) then parseInt(res.match[1].trim(), 10) else n
    if isInvalidIndex(n)
        res.send "Invalid game index #{n}"
        return

    game = games[n]
    playerIndex = game.indexOf(senderPlayer)
    if playerIndex < 0
        res.send "#{senderPlayer} is not part of Game #{n}"
        return

    game[playerIndex] = '_'
    saveGames()

    # TODO: Abandon the nth game, freeing your spot in it
    remainingPlayers = [(player for player in game when player != "_")].join(', ')
    res.send "#{senderPlayer} abandoned game #{n}. Remaining players: #{remainingPlayers}"

    gamesRespond(res)


cancelGameRespond = (res, n) ->
    n = if isUndefined(n) then parseInt(res.match[1].trim(), 10) else n
    if isInvalidIndex(n)
        res.send "Invalid game index #{n}"
        return

    games.splice(n, 1)
    saveGames()

    # TODO: Cancel the nth game
    res.send "Game #{n} cancelled"

    gamesRespond(res)


findPeopleForNextGameRespond = (res) ->
    # Ask @all who's up for a game, and announce who's currently part of the next upcoming game
    findPeopleForGameRespond(res, 0)


joinNextGameRespond = (res) ->
    # Add yourself to the next game
    # Cannot join if full
    joinGameRespond(res, 0)


abandonNextGameRespond = (res) ->
    # Abandon the next upcoming game, freeing your spot in it
    abandonGameRespond(res, 0)


cancelNextGameRespond = (res) ->
    # Cancel the next upcoming game
    cancelGameRespond(res, 0)


finishGameRespond = (res) ->
    if games.length <= 0
        res.send "No games are being played at the moment"
        return

    team1_p1 = res.match[1].trim()
    team1_p2 = res.match[2].trim()

    team2_p1 = res.match[3].trim()
    team2_p2 = res.match[4].trim()

    team1_score = parseInt(res.match[5].trim(), 10)
    team2_score = parseInt(res.match[6].trim(), 10)

    all_players = [team1_p1,team1_p2,team2_p1,team2_p2]

    # Ensure no invalid or duplicate players were specified
    if all_players.indexOf('_') >= 0
        res.send "'_' is not a valid player. Nice try."
        return
    if new Set(all_players).size < 4
        res.send "Cannot specify duplicate players"
        return

    # Ensure that all players are in the next game to play
    game = games[0]
    for team_member in all_players
        if (game.indexOf(team_member) < 0)
            res.send "#{team_member} is not part of the current game being played"
            return

    # The following is the format for game results
    result = {
        'team1': {
            'player1': team1_p1,
            'player2': team1_p2,
            'score': team1_score
        },
        'team2': {
            'player1': team2_p1,
            'player2': team2_p2,
            'score': team2_score
        }
    }

    # TODO: Record the scores and save them
    finishedGames.push result
    saveFinishedGames()

    # Remove the game from the list
    games.splice(0,1)

    res.send "Result saved"

addToGameRespond = (res, n) ->
    # Add a player to the nth game
    playerName = res.match[1].trim()
    n = if isUndefined(n) then parseInt(res.match[2].trim(), 10) else n

    joinGameRespond(res, n, playerName)

addToNextGameRespond = (res) ->
    # Add yourself to the next game
    # Cannot join if full
    addToGameRespond(res, 0)


kickFromGameRespond = (res, n) ->
    # Kick a player from the nth game
    playerName = res.match[1].trim()
    n = if isUndefined(n) then parseInt(res.match[2].trim(), 10) else n

    abandonGameRespond(res, n, playerName)

kickFromNextGameRespond = (res) ->
    # Kick a player from the next game
    kickFromGameRespond(res, 0)


module.exports = (robot) ->
    robot.respond /games/i, gamesRespond

    robot.respond /find people for game (\d+)/i, findPeopleForGameRespond
    robot.respond /join game (\d+)/i, joinGameRespond
    robot.respond /add (\w+) to game (\d+)/i, addToGameRespond
    robot.respond /kick (\w+) from game (\d+)/i, kickFromGameRespond
    robot.respond /abandon game (\d+)/i, abandonGameRespond
    robot.respond /cancel game (\d+)/i, cancelGameRespond

    robot.respond /start game/i, startGameRespond
    robot.respond /find people$/i, findPeopleForNextGameRespond
    robot.respond /i'm in/i, joinNextGameRespond
    robot.respond /join game$/i, joinNextGameRespond
    robot.respond /add (\w+)$/i, addToNextGameRespond
    robot.respond /kick (\w+)$/i, kickFromNextGameRespond
    robot.respond /abandon game$/i, abandonNextGameRespond
    robot.respond /cancel game$/i, cancelNextGameRespond

    robot.respond /finish game: +(\w+) +and +(\w+) +vs\.? +(\w+) +and +(\w+), +final +score +(\d+) *- *(\d+)$/i, finishGameRespond
