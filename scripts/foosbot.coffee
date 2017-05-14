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
#   foosbot Finish game <team1_score>-<team2_score> - Finish the next game and record the results
#   foosbot Rankings|Leaderboard - Show the leaderboard
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


rightPad = (s, finalLength) ->
  numSpaces = Math.max(0, finalLength - s.length)
  return s + ' '.repeat(numSpaces)


round = (num, decimals) ->
  return Number(Math.round(num+'e'+decimals)+'e-'+decimals);


gamesRespond = (res) ->
  # TODO: List the games, in groups of 4, with the indices
  if games.length <= 0
    res.send "No games started"
    return

  responseLines = []
  for game, index in games
    team1 = "#{game[0]} and #{game[1]}"
    team2 = "#{game[2]} and #{game[3]}"
    responseLines.push "Game #{index}:\n#{team1}\nvs.\n#{team2}\n"

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

initOrRetrievePlayerStat = (stats, playerName) ->
    if playerName of stats
        return stats[playerName]
    
    return {
        "gamesPlayed": 0,
        "gamesWon": 0,
        "winPercentage": 0
    }

getStats = () ->
    # Return stats for all players, which is a map from player name to object with games played, games won, and win percentage
    stats = {}
    for finishedGame in finishedGames
        t1p1 = finishedGame['team1']['player1']
        t1p2 = finishedGame['team1']['player2']
        t2p1 = finishedGame['team2']['player1']
        t2p2 = finishedGame['team2']['player2']

        t1score = finishedGame['team1']['score']
        t2score = finishedGame['team2']['score']

        all_players = [t1p1, t1p2, t2p1, t2p2]
        for player in all_players
            stats[player] = initOrRetrievePlayerStat(stats, player)
            stats[player]['gamesPlayed'] += 1

        if t1score > t2score
            stats[t1p1]['gamesWon'] += 1
            stats[t1p2]['gamesWon'] += 1
        else if t2score > t1score
            stats[t2p1]['gamesWon'] += 1
            stats[t2p2]['gamesWon'] += 1
    
    for player in Object.keys(stats)
        stats[player]['winPercentage'] = round((stats[player]['gamesWon'] / stats[player]['gamesPlayed']) * 100, 2)

    return stats


rankSort = (p1, p2) ->
    # Try sorting by winPercentage first
    if p1['winPercentage'] > p2['winPercentage']
        return -1
    else if p1['winPercentage'] < p2['winPercentage']
        return 1
    
    # If win percentage is the same, sort by games won
    if p1['gamesWon'] > p2['gamesWon']
        return -1
    else if p1['gamesWon'] < p2['gamesWon']
        return 1

    # If games won is the same, sort by games played
    if p1['gamesPlayed'] >= p2['gamesPlayed']
        return -1
    else if p1['gamesPlayed'] < p2['gamesPlayed']
        return 1


noopFormat = (str) -> return "#{str}"
percentFormat = (str) -> return "#{str}%"

addColumn = (lines, stats, header, field, formatFunc) ->
  isIndexColumn = !field
  formatFunc = if isUndefined(formatFunc) then noopFormat else formatFunc

  # Calculate the longest length, for padding
  header = if isIndexColumn then "Rank" else "#{header}"
  longestLength = header.length
  for stat, index in stats
    fieldValue = if isIndexColumn then "#{index}" else formatFunc(stat[field])

    longestLength = Math.max(longestLength, fieldValue.length)

  longestLength += 1

  # Add the header and the underline
  headerLength = longestLength + 2
  lines[0] += rightPad(header, headerLength)
  lines[1] += '-'.repeat(headerLength)

  # Add the column for each statistic
  for stat, index in stats
    if isIndexColumn
      fieldValue = rightPad("#{index+1}", longestLength)
      lines[2+index] += fieldValue
    else
      fieldValue = rightPad(formatFunc(stat[field]), longestLength)
      lines[2+index] += "| #{fieldValue}"


rankingsRespond = (res) ->
    # Get the stats for each player
    stats = getStats()

    # Add the name and make a sortable array
    statsArray = []
    for player in Object.keys(stats)
        playerStats = stats[player]
        playerStats["name"] = player
        statsArray.push playerStats

    # Sort the players based on rank
    statsArray.sort(rankSort)

    # Construct the rankings string
    responseList = new Array(statsArray.length + 2).fill('') # Initialize with empty lines, to add to later
    addColumn(responseList, statsArray, "", "", ) # Index column
    addColumn(responseList, statsArray, "Player", "name")
    addColumn(responseList, statsArray, "Win Percentage", "winPercentage", percentFormat)
    addColumn(responseList, statsArray, "Games Won", "gamesWon")
    addColumn(responseList, statsArray, "Games Played", "gamesPlayed")
    
    res.send responseList.join('\n')

balancePlayers = (game) ->
    # TODO: Balance based on rank
    return game

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
                balancePlayers(game)
                gamePlayers = game.map (player) -> "@#{player}"
                teamsStr = "#{gamePlayers[0]} and #{gamePlayers[1]}\nvs.\n#{gamePlayers[2]} and #{gamePlayers[3]}"
                res.send "#{gameStr} is ready to go! Teams:\n#{teamsStr}"

            saveGames()

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

    game = games[0]
    if game.indexOf('_') >= 0
        res.send "Next game isn't ready to go yet'"
        return

    # The following is the format for game results
    result = {
        'team1': {
            'player1': game[0].trim(),
            'player2': game[1].trim(),
            'score': parseInt(res.match[1].trim(), 10)
        },
        'team2': {
            'player1': game[2].trim(),
            'player2': game[3].trim(),
            'score': parseInt(res.match[2].trim(), 10)
        }
    }

    # Record the scores and save them
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

    robot.respond /finish game +(\d) *- *(\d)$/i, finishGameRespond
    robot.respond /(rankings|leaderboard)$/i, rankingsRespond
