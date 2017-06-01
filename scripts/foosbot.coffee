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
#   foosbot Balance game - Balance the next game based on player ranks
#   foosbot Shuffle game - Randomly shuffle the players in the next game
#   foosbot Find people for game <n> - Ask for people to play in the nth game
#   foosbot Join game <n> - Claim a spot in the nth game
#   foosbot Add <player_name> to game <n> - Add a player that may or may not be on LCB to the nth game
#   foosbot Kick <player_name> from game <n> - Kick a player from the nth game
#   foosbot Abandon game <n> - Free up your spot in the nth game
#   foosbot Cancel game <n> - Cancel the nth game
#   foosbot Balance game <n> - Balance the nth game based on player ranks
#   foosbot Shuffle game <n> - Randomly shuffle the players in the nth game
#   foosbot Finish game <team1_score>-<team2_score>, ... - Finish the next game and record the results (of possibly multiple games)
#   foosbot Rankings|Leaderboard - Show the leaderboard
#
# Author:
#   MartinPetkov

fs = require 'fs'
ts = require 'trueskill'

gamesFile = 'games.json'
finishedGamesFile = 'finishedgames.json'
previousRanksFile = 'previousranks.json'


loadFile = (fileName) ->
    return JSON.parse((fs.readFileSync fileName, 'utf8').toString().trim())

games = loadFile(gamesFile)
finishedGames = loadFile(finishedGamesFile)
previousRanks = loadFile(previousRanksFile)

saveGames = () ->
  fs.writeFileSync(gamesFile, JSON.stringify(games))

saveFinishedGames = () ->
  fs.writeFileSync(finishedGamesFile, JSON.stringify(finishedGames))

savePreviousRanks = () ->
  fs.writeFileSync(previousRanksFile, JSON.stringify(previousRanks))


# Date diff calculations
_MS_PER_DAY = 1000 * 60 * 60 * 24
diffDays = (date1, date2) ->
    return Math.round((date1 - date2) / _MS_PER_DAY, 0)

# Store list of datetimes of previous plays
_SHAME_MESSAGES = [
    "Playing again, huh?",
    "Shouldn't you be doing...work?",
    "Wow, look at your rank after all these games you've played!",
    "You could have finished that ticket in the time you've spent playing foosball today",
    "Aren't your hands tired by now?",
    "Maybe it's time you took a break from foos",
    "Are you /really/ sure you want to keep playing today?",
]
_DEFAULT_SHAME_MESSAGE = "Maximum slack level reached, HR has been notified"
getShameMsg = (res, player, timesPlayed) ->
    shameMsg = if timesPlayed >= 10 then _DEFAULT_SHAME_MESSAGE else res.random _SHAME_MESSAGES
    return "@#{player} #{shameMsg}"

# Store shame
shameFile = 'shame.json'
shame = JSON.parse((fs.readFileSync shameFile, 'utf8').toString().trim())
for player of shame
    shame[player] = shame[player].map (playTime) -> new Date(playTime)

saveShame = () ->
  fs.writeFileSync(shameFile, JSON.stringify(shame))

# Shame players who play too much
updateShame = (player) ->
    if !(player of shame)
        shame[player] = []

    now = new Date()
    shame[player].push now
    saveShame()

shameSlacker = (res, player) ->
    player = player.trim().toLowerCase()
    if !(player of shame)
        return

    # Remove all recorded plays older than 1 day and not on the same calendar date
    now = new Date()
    shame[player] = shame[player].filter (playTime) -> (diffDays(now, playTime) == 0) && (playTime.getDate() == now.getDate())
    saveShame()

    timesPlayed = shame[player].length
    if timesPlayed >= 3
        res.send getShameMsg(res, player, timesPlayed)


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
  # Create a new group of four, at the end of the games array
  captain = res.message.user.name
  games.push [captain, '_', '_', '_']
  saveGames()

  shameSlacker(res, captain)

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
        "winPercentage": 0,
        "skill": [25.0, 25.0/3.0],
        "rank": 2
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

        allPlayers = [t1p1, t1p2, t2p1, t2p2]
        for player in allPlayers
            stats[player] = initOrRetrievePlayerStat(stats, player)
            stats[player]['gamesPlayed'] += 1
            stats[player]['rank'] = 2

        if t1score > t2score
            stats[t1p1]['gamesWon'] += 1
            stats[t1p2]['gamesWon'] += 1
            stats[t1p1]['rank'] = 1
            stats[t1p2]['rank'] = 1
        else if t2score > t1score
            stats[t2p1]['gamesWon'] += 1
            stats[t2p2]['gamesWon'] += 1
            stats[t2p1]['rank'] = 1
            stats[t2p2]['rank'] = 1

        ts.AdjustPlayers([stats[t1p1], stats[t1p2], stats[t2p1], stats[t2p2]])
    
    for player in Object.keys(stats)
        stats[player]['name'] = player
        stats[player]['winPercentage'] = round((stats[player]['gamesWon'] / stats[player]['gamesPlayed']) * 100, 2)
        stats[player]['trueskill'] = stats[player]['skill'][0] - (3 * stats[player]['skill'][1])

    return stats

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


skillSort = (p1, p2) ->
    # High ranks are pushed to the front
    if p1['trueskill'] > p2['trueskill']
        return -1
    if p1['trueskill'] < p2['trueskill']
        return 1

    # Order by games won next
    if p1['gamesWon'] > p2['gamesWon']
        return -1
    if p1['gamesWon'] < p2['gamesWon']
        return 1

    # Order by win percentage last
    return if p1['winPercentage'] >= p2['winPercentage'] then -1 else 1

getRankings = () ->
    # Get the stats for each player
    stats = getStats()

    # Make a sortable array
    rankings = []
    for player in Object.keys(stats)
        rankings.push stats[player]

    # Sort the players based on rank
    rankings.sort(skillSort)

    return rankings

rankingsRespond = (res) ->
    # Get the player rankings
    rankings = getRankings()

    # Construct the rankings string
    responseList = new Array(rankings.length + 2).fill('') # Initialize with empty lines, to add to later
    addColumn(responseList, rankings, "", "", ) # Index column
    addColumn(responseList, rankings, "Player", "name")
    addColumn(responseList, rankings, "Trueskill", "trueskill")
    addColumn(responseList, rankings, "Win Percentage", "winPercentage", percentFormat)
    addColumn(responseList, rankings, "Games Won", "gamesWon")
    addColumn(responseList, rankings, "Games Played", "gamesPlayed")
    
    res.send responseList.join('\n')


resetPreviousRankings = (res) ->
    rankings = getRankings()
    for player, rank in rankings
        previousRanks[player['name']] = rank + 1

    savePreviousRanks()
    
    res.send "Previous rankings reset to current rankings"


showChangedRankings = (res, p1, p2, p3, p4) ->
    rankChanges = "Rank changes:\n"

    rankings = getRankings()

    for p in [p1,p2,p3,p4]
        curRank = getRank(p, rankings) + 1
        console.log
        if p of previousRanks
            prevRank = previousRanks[p]
            rankDiff = prevRank - curRank
            prefix = if rankDiff < 0 then '' else '+'
        else
            rankDiff = curRank
            prefix = '~'

        rankChanges += "#{prefix}#{rankDiff} -> #{curRank} #{p}\n"

        previousRanks[player] = curRank

    savePreviousRanks()

    res.send rankChanges


rankSort = (p1,p2) ->
    # Negative rank means the player isn't ranked
    if p1['rank'] < 0
        return -1
    if p2['rank'] < 0
        return 1

    # A low rank is better than a high rank
    return if p1['rank'] <= p2['rank'] then -1 else 1


getRank = (playerName, rankings) ->
    for player, rank in rankings
        if player['name'] == playerName
            return rank

    return -1


balancePlayers = (game) ->
    # Get the player rankings, which are sorted correctly
    rankings = getRankings()

    # Balance based on rank
    playersWithRanks = game.map (player) -> {"name": player, "rank": getRank(player, rankings)}
    playersWithRanks.sort(rankSort)

    # Update the game
    game[0] = playersWithRanks[0]["name"]
    game[1] = playersWithRanks[3]["name"]
    game[2] = playersWithRanks[1]["name"]
    game[3] = playersWithRanks[2]["name"]

shufflePlayers = (game) ->
    i = game.length
    while --i
        j = Math.floor(Math.random() * (i+1))
        [game[i], game[j]] = [game[j], game[i]] # use pattern matching to swap

joinGameRespond = (res, n, playerName) ->
    newPlayer = if isUndefined(playerName) then res.message.user.name else playerName
    n = if isUndefined(n) then parseInt(res.match[1].trim(), 10) else n
    any = if !any then false else true
    if isInvalidIndex(n)
        res.send "Invalid game index #{n}"
        return

    shameSlacker(res, newPlayer)

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


balanceGameRespond = (res, n) ->
    n = if isUndefined(n) then parseInt(res.match[1].trim(), 10) else n
    if isInvalidIndex(n)
        res.send "Invalid game index #{n}"
        return

    balancePlayers(games[n])
    saveGames()
    gamesRespond(res)

    res.send "Game #{n} balanced based on rank"

balanceNextGameRespond = (res) ->
    balanceGameRespond(res, 0)


shuffleGameRespond = (res, n) ->
    n = if isUndefined(n) then parseInt(res.match[1].trim(), 10) else n
    if isInvalidIndex(n)
        res.send "Invalid game index #{n}"
        return

    shufflePlayers(games[n])
    saveGames()
    gamesRespond(res)

    res.send "Game #{n} randomly shuffled"

shuffleNextGameRespond = (res) ->
    shuffleGameRespond(res, 0)


finishGameRespond = (res) ->
    if games.length <= 0
        res.send "No games are being played at the moment"
        return

    game = games[0]
    if game.indexOf('_') >= 0
        res.send "Next game isn't ready to go yet!"
        return

    results = res.match[1].trim().split(",")
    for result in results
        result = result.trim().split('-')
        t1score = parseInt(result[0], 10)
        t2score = parseInt(result[1], 10)

        t1p1 = game[0].trim().toLowerCase()
        t1p2 = game[1].trim().toLowerCase()
        t2p1 = game[2].trim().toLowerCase()
        t2p2 = game[3].trim().toLowerCase()

        # The following is the format for game results
        resultDetails = {
            'team1': {
                'player1': t1p1,
                'player2': t1p2,
                'score': t1score
            },
            'team2': {
                'player1': t2p1,
                'player2': t2p2,
                'score': t2score
            }
        }

        for player in [t1p1,t1p2,t2p1,t2p2]
            updateShame(player)

        # Record the scores and save them
        finishedGames.push resultDetails

    saveFinishedGames()

    # Show changed rankings since last time
    showChangedRankings(res, t1p1, t1p2, t2p1, t2p2)

    # Remove the game from the list
    games.splice(0,1)
    saveGames()

    res.send "Results saved"


module.exports = (robot) ->
    robot.respond /games/i, gamesRespond

    robot.respond /find people for game (\d+)/i, findPeopleForGameRespond
    robot.respond /join game (\d+)/i, joinGameRespond
    robot.respond /add (\w+) to game (\d+)/i, addToGameRespond
    robot.respond /kick (\w+) from game (\d+)/i, kickFromGameRespond
    robot.respond /abandon game (\d+)/i, abandonGameRespond
    robot.respond /cancel game (\d+)/i, cancelGameRespond
    robot.respond /balance game (\d+)/i, balanceGameRespond
    robot.respond /shuffle game (\d+)/i, shuffleGameRespond

    robot.respond /start game/i, startGameRespond
    robot.respond /find people$/i, findPeopleForNextGameRespond
    robot.respond /i'm in/i, joinNextGameRespond
    robot.respond /join game$/i, joinNextGameRespond
    robot.respond /add (\w+)$/i, addToNextGameRespond
    robot.respond /kick (\w+)$/i, kickFromNextGameRespond
    robot.respond /abandon game$/i, abandonNextGameRespond
    robot.respond /cancel game$/i, cancelNextGameRespond
    robot.respond /balance game$/i, balanceNextGameRespond
    robot.respond /shuffle game$/i, shuffleNextGameRespond

    robot.respond /finish game +((\d-\d)( *, *\d-\d)*)$/i, finishGameRespond
    robot.respond /(rankings|leaderboard)$/i, rankingsRespond
    robot.respond /reset previous rankings$/i, resetPreviousRankings
