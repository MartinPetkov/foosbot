# Description:
#   An LCB bot that arranges foosball games
#
# Commands:
#   foosbot Games - List currently scheduled games
#   foosbot Total games - Return the number of total games
#   foosbot Start game - Start a new game, always added to the end of the queue
#   foosbot Start game with <p1> [<p2> <p3>] - Start a new game, always added to the end of the queue, with multiple people
#   foosbot Find people|players - Ask for people to play in the next game
#   foosbot I'm in | Join game - Claim a spot in the next game
#   foosbot Add <player_name> - Add a player that may or may not be on LCB to the next game
#   foosbot Kick <player_name> - Kick a player from the next game
#   foosbot Abandon game - Free up your spot in the next game
#   foosbot Cancel game - Cancel the next game
#   foosbot Balance game - Balance the next game based on player ranks
#   foosbot Shuffle game - Randomly shuffle the players in the next game
#   foosbot Find people|players for game <n> - Ask for people to play in the nth game
#   foosbot Join game <n> - Claim a spot in the nth game
#   foosbot Add <player_name> to game <n> - Add a player that may or may not be on LCB to the nth game
#   foosbot Kick <player_name> from game <n> - Kick a player from the nth game
#   foosbot Abandon game <n> - Free up your spot in the nth game
#   foosbot Cancel game <n> - Cancel the nth game
#   foosbot Balance game <n> - Balance the nth game based on player ranks
#   foosbot Shuffle game <n> - Randomly shuffle the players in the nth game
#   foosbot Finish game <team1_score>-<team2_score>, ... - Finish the next game and record the results (of possibly multiple games)
#   foosbot Rematch - Repair your pride by playing the same game you just lost
#   foosbot Go on [a] cleanse - Go on a cleanse, unable to be added to a game
#   foosbot Return from cleanse - Return refreshed, ready to take on the champions
#   foosbot Rankings|Leaderboard - Show the leaderboard
#   foosbot Rankings|Stats <player1> [<player2> ...] - Show the stats for specific players
#   foosbot Top <n> - Show the top n players in the rankings
#   foosbot History <player>|me [<numPastGames>] - Show a summary of your past games
#   foosbot Team Stats <playerOne>|me <playerTwo>|me|all - Shows the team stats for two players, or all pairings of <playerOne>
#   foosbot The rules - Show the rules we play by
#
# Author:
#   MartinPetkov

fs = require 'fs'
ts = require 'trueskill'

gamesFile = 'games.json'
finishedGamesFile = 'finishedgames.json'
previousRanksFile = 'previousranks.json'
cleanseFile = 'cleanse.json'


loadFile = (fileName, initialValue) ->
    # Initialize the file if it does not exist
    if !(fs.existsSync(fileName))
        fs.writeFileSync(fileName, JSON.stringify(initialValue))

    return JSON.parse((fs.readFileSync fileName, 'utf8').toString().trim())

games = loadFile(gamesFile, [])
finishedGames = loadFile(finishedGamesFile, [])
previousRanks = loadFile(previousRanksFile, {})
cleanse = loadFile(cleanseFile, [])

saveGames = () ->
    fs.writeFileSync(gamesFile, JSON.stringify(games))

saveFinishedGames = () ->
    fs.writeFileSync(finishedGamesFile, JSON.stringify(finishedGames))

savePreviousRanks = () ->
    fs.writeFileSync(previousRanksFile, JSON.stringify(previousRanks))

saveCleanse = () ->
    fs.writeFileSync(cleanseFile, JSON.stringify(cleanse))


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
    # List the games, in groups of 4, with the indices
    if games.length <= 0
        res.send "No games started"
        return

    responseLines = []
    for game, index in games
        team1 = "#{game[0]} and #{game[1]}"
        team2 = "#{game[2]} and #{game[3]}"
        responseLines.push "Game #{index}:\n#{team1}\nvs.\n#{team2}\n"

    res.send responseLines.join('\n')


startGameRespond = (res, startingPlayers) ->
    # Create a new group of four, at the end of the games array
    captain = res.message.user.name
    if captain in cleanse
        res.reply "You can't start any games, you're on a cleanse!"
        return

    games.push [captain, '_', '_', '_']
    saveGames()

    shameSlacker(res, captain)

    res.send "New game started"

    if !(isUndefined(startingPlayers))
        n = games.length - 1
        for sp in startingPlayers
            joinGameRespond(res, n, sp)

    gamesRespond(res)

startGameWithPlayersRespond = (res) ->
    startingPlayers = (name.trim() for name in res.match[1].trim().split(' '))
    res.send "Starting players: #{startingPlayers}"
    startGameRespond(res, startingPlayers)


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
        "rank": 2,
        "streak": 0,
        "longestWinStreak": 0,
        "longestLoseStreak": 0,
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

        winPlayers = []
        losePlayers = []
        if t1score > t2score
            winPlayers = [t1p1, t1p2]
            losePlayers = [t2p1, t2p2]
        else if t2score > t1score
            winPlayers = [t2p1, t2p2]
            losePlayers = [t1p1, t1p2]

        for wp in winPlayers
            stats[wp]['gamesWon'] += 1
            stats[wp]['rank'] = 1

            # If they were losing until this game, reset them to a 1 win streak
            stats[wp]['streak'] = if stats[wp]['streak'] < 0 then 1 else stats[wp]['streak'] + 1
            if stats[wp]['streak'] > stats[wp]['longestWinStreak']
                stats[wp]['longestWinStreak'] = stats[wp]['streak']

        for lp in losePlayers
            # If they were winning until this game, reset them to a 1 lose streak
            stats[lp]['streak'] = if stats[lp]['streak'] > 0 then -1 else stats[lp]['streak'] - 1

            if -stats[lp]['streak'] > stats[lp]['longestLoseStreak']
                stats[lp]['longestLoseStreak'] = -stats[lp]['streak']

        ts.AdjustPlayers([stats[t1p1], stats[t1p2], stats[t2p1], stats[t2p2]])

    for player in Object.keys(stats)
        stats[player]['name'] = player
        stats[player]['winPercentage'] = round((stats[player]['gamesWon'] / stats[player]['gamesPlayed']) * 100, 2)
        stats[player]['trueskill'] = stats[player]['skill'][0] - (3 * stats[player]['skill'][1])

    return stats

noopFormat = (str) -> return "#{str}"
fixedTwoFormat = (str) -> return "#{str.toFixed(2)}"
trueskillFormat = (str) -> return "#{str.toFixed(5)}"
percentFormat = (str) -> return "#{str}%    "
gamesFormat = (str) -> return "#{str} game#{if str == 1 then '' else 's'}"
streakFormat = (str) ->
    winning = str > 0
    gameStreak = if winning then str else -str
    return "#{if winning then ':fire:' else ':poop:'} #{gameStreak} #{if winning then 'won' else 'lost'}"

addColumn = (lines, stats, header, field, formatFunc, isFirstColumn) ->
    isIndexColumn = !field
    formatFunc = if isUndefined(formatFunc) then noopFormat else formatFunc

    # Calculate the longest length, for padding
    header = if isIndexColumn then "Rank" else "#{header}"
    longestLength = header.length
    longestHeaderLength = header.length
    for stat, index in stats
        fieldValue = if isIndexColumn then "#{index}" else formatFunc(stat[field])

        longestLength = Math.max(longestLength, fieldValue.length)

        # Convert emojis to a single character
        collapsedFieldValue = fieldValue
        collapsedFieldValue = collapsedFieldValue.replace /:.*:/g, (txt) -> ':::'
        longestHeaderLength = Math.max(longestHeaderLength, collapsedFieldValue.length)

    longestLength += 1
    longestHeaderLength += 1

    # Add the header and the underline
    headerLength = longestHeaderLength + 2
    lines[0] += rightPad(header, headerLength)
    lines[1] += '-'.repeat(headerLength)

    # Add the column for each statistic
    for stat, index in stats
        if isIndexColumn
            fieldValue = rightPad("#{index+1}", longestLength)
        else
            fieldValue = rightPad(formatFunc(stat[field]), longestLength)

        if !isFirstColumn
            lines[2+index] += "| "

        lines[2+index] += "#{fieldValue}"


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

    for stat, rank in rankings
        stat['rank'] = rank + 1

    return rankings

rankingsRespond = (res, specificPlayers, topNPlayers) ->
    # Get the player rankings
    rankings = getRankings()

    # Either filter or show topNPlayers players, but not both
    if !(isUndefined(specificPlayers))
        rankings = rankings.filter (stat) -> stat["name"] in specificPlayers
    else if !(isUndefined(topNPlayers))
        rankings = rankings.slice(0, topNPlayers)

    # Construct the rankings string
    responseList = new Array(rankings.length + 2).fill('') # Initialize with empty lines, to add to later
    # addColumn(responseList, rankings, "", "", ) # Index column
    addColumn(responseList, rankings, "Rank", "rank", noopFormat, true)
    addColumn(responseList, rankings, "Player", "name")
    addColumn(responseList, rankings, "Trueskill", "trueskill", trueskillFormat)
    addColumn(responseList, rankings, "Win %", "winPercentage", percentFormat)
    addColumn(responseList, rankings, "Won", "gamesWon")
    addColumn(responseList, rankings, "Played", "gamesPlayed")
    addColumn(responseList, rankings, "Streak", "streak", streakFormat)
    addColumn(responseList, rankings, "Longest Win Streak", "longestWinStreak", gamesFormat)
    addColumn(responseList, rankings, "Longest Lose Streak", "longestLoseStreak", gamesFormat)

    res.send responseList.join('\n')

rankingsForPlayersRespond = (res) ->
    players = (name.trim() for name in res.match[1].trim().split(' '))
    rankingsRespond(res, players)

topNRankingsRespond = (res) ->
    n = res.match[1].trim()
    rankingsRespond(res, undefined, n)


resetPreviousRankings = (res) ->
    rankings = getRankings()
    for player, rank in rankings
        previousRanks[player['name']] = rank + 1

    savePreviousRanks()


showChangedRankings = (res, p1, p2, p3, p4) ->
    rankChanges = "Rank changes:\n"

    rankings = getRankings()

    for p in [p1,p2,p3,p4]
        curRank = getRank(p, rankings) + 1
        if p of previousRanks
            prevRank = previousRanks[p]
            rankDiff = prevRank - curRank
            prefix = if rankDiff < 0 then '' else '+'
        else
            rankDiff = curRank
            prefix = '='

        rankChanges += "#{prefix}#{rankDiff} -> #{curRank} #{p}\n"

    resetPreviousRankings(res)

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

    # If the player is new, they should be considered worse than anyone
    return Infinity


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
    if newPlayer in cleanse
        if isUndefined(playerName)
            res.reply "You can't join any games, you're on a cleanse!"
        else
            res.send "#{newPlayer} cannot join games, they are on a cleanse! "
        return

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
                teamOneWinRate = getTeamStats(game[0], game[1])[game[1]]["winPercentage"]
                teamTwoWinRate = getTeamStats(game[2], game[3])[game[3]]["winPercentage"]

                teamsStr = "#{gamePlayers[0]} and #{gamePlayers[1]} (#{teamOneWinRate}%)\n"
                teamsStr += "vs.\n"
                teamsStr += "#{gamePlayers[2]} and #{gamePlayers[3]} (#{teamTwoWinRate}%)"
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

    # Abandon the nth game, freeing your spot in it
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

    # Cancel the nth game
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

theRulesRespond = (res) ->
    res.send [
        "No spinning",
        "If someone scores with the first shot, it doesn't count",
        "If someone scores by hitting the ball before it reaches the far wall, it doesn't count",
        "Any player can score from any position",
        "When one team reaches 5 points, both teams switch defense/offense players",
        "If a shot goes in but comes out, it counts as long as it made the *dank* sound",
        "The last goal cannot be an own goal, it must be scored by the opposing team",
        "If unsure whether a goal counts, the team that got scored on makes the call",
        "If the ball goes dead anywhere except the far sides, reset to the middle",
        "If the ball goes dead on a far side, defense resets it from a corner",
        "If the ball flies off the table, reset to the middle",
        "If it wasn't organized by foosbot, it's a friendly game and does not affect rankings",
        "Everyone shakes hands at the end of the game, no exceptions",
        ].map((rule, i) -> "#{i+1}. #{rule}").join('\n')


goOnACleanseRespond = (res) ->
    senderName = res.message.user.name
    if !(senderName in cleanse)
        cleanse.push senderName

    saveCleanse()

    res.reply "You are now on a cleanse. Stay away from the foosball table, and relax :palm_tree:"

returnFromCleanseRespond = (res) ->
    senderName = res.message.user.name

    if !(senderName in cleanse)
        res.reply "You are not on a cleanse, go play some foos!"
        return

    cleanse.splice(cleanse.indexOf(senderName), 1)
    saveCleanse()

    res.reply "Welcome back! Now go kick some ass"


initTeamStat = (stats, playerName) ->
    stats[playerName] = {
        "wins": 0,
        "losses": 0,
        "ties": 0,
        "goalsFor": 0,
        "goalsAgainst": 0,
        "winPercentage": 0,
        "avgGoalsFor": 0,
        "avgGoalsAgainst": 0
    }

getTeamStats = (playerOneName, playerTwoName) ->
    # Allow getting stats for all team pairings by providing "all" as the playerTwoName
    # The keys of the return dictionary are the names of the other team member

    stats = {}

    playerOneName = playerOneName.toLowerCase()
    playerTwoName = playerTwoName.toLowerCase()

    # Make sure the partner has the default stats
    if !(playerTwoName == 'all')
        initTeamStat(stats, playerTwoName)

    for finishedGame in finishedGames
        teamOne = [finishedGame["team1"]["player1"], finishedGame["team1"]["player2"]]
        teamTwo = [finishedGame["team2"]["player1"], finishedGame["team2"]["player2"]]

        if playerOneName in teamOne && (playerTwoName == 'all' || playerTwoName in teamOne)
            myTeam = finishedGame["team1"]
            otherTeam = finishedGame["team2"]
        else if playerOneName in teamTwo && (playerTwoName == 'all' || playerTwoName in teamTwo)
            myTeam = finishedGame["team2"]
            otherTeam = finishedGame["team1"]
        else
            continue

        # Get the partner's name
        partnerName = if myTeam["player1"] == playerOneName then myTeam["player2"] else myTeam["player1"]
        if !(partnerName of stats)
            initTeamStat(stats, partnerName)

        partnerStats = stats[partnerName]

        if myTeam["score"] > otherTeam["score"]
            partnerStats["wins"] += 1
        else if myTeam["score"] == otherTeam["score"]
            partnerStats["ties"] += 1
        else
            partnerStats["losses"] += 1

        partnerStats["goalsFor"] += myTeam["score"]
        partnerStats["goalsAgainst"] += otherTeam["score"]

    # Extra Stats
    for partnerName of stats
        partnerStats = stats[partnerName]

        gamesPlayed = partnerStats["wins"] + partnerStats["losses"] + partnerStats["ties"]
        if gamesPlayed > 0
            partnerStats["winPercentage"] = ((partnerStats["wins"] / gamesPlayed) * 100).toFixed(2)
            partnerStats["avgGoalsFor"] = partnerStats["goalsFor"] / gamesPlayed
            partnerStats["avgGoalsAgainst"] = partnerStats["goalsAgainst"] / gamesPlayed

    return stats


teamStatsRespond = (res) ->
    playerOneName = if res.match[1] == 'me' then res.message.user.name else res.match[1].trim().toLowerCase()
    playerTwoName = if res.match[2] == 'me' then res.message.user.name else res.match[2].trim().toLowerCase()

    if playerOneName == playerTwoName
        res.send "Player one and player two cannot be the same."
        return

    teamStats = getTeamStats(playerOneName, playerTwoName)

    # Build the response of stats for all team pairings
    response = ''
    for partnerName of teamStats
        partnerStats = teamStats[partnerName]

        responseList = new Array(3).fill('')
        addColumn(responseList, [partnerStats], "Win", "wins", noopFormat, true)
        addColumn(responseList, [partnerStats], "Loss", "losses")
        addColumn(responseList, [partnerStats], "Tie", "ties")
        addColumn(responseList, [partnerStats], "Avg. Goals For", "avgGoalsFor", fixedTwoFormat)
        addColumn(responseList, [partnerStats], "Avg. Goals Against", "avgGoalsAgainst", fixedTwoFormat)
        addColumn(responseList, [partnerStats], "Win Rate", "winPercentage", percentFormat)

        response += "Team: #{playerOneName} and #{partnerName}\n"
        response += responseList.join("\n")
        response += "\n\n\n"

    res.send response


historyRespond = (res) ->
    me = res.match[1] == 'me'
    playerName = if me then res.message.user.name else res.match[1].trim()

    numPastGames = if isUndefined(res.match[2]) then 5 else parseInt(res.match[2].trim(), 10)
    gamesFound = 0
    pastGames = []

    # Collect the last n games
    for i in [finishedGames.length-1..0] by -1
        fgame = finishedGames[i]

        if playerName in [fgame["team1"]["player1"], fgame["team1"]["player2"], fgame["team2"]["player1"], fgame["team2"]["player2"]]
            pastGames.unshift(fgame)
            gamesFound += 1

            if gamesFound >= numPastGames
                break

    pronoun = if me then 'Your' else "#{playerName}'s"
    strGames = "#{pronoun} last #{numPastGames} games:"
    for pg, i in pastGames
        score = '\t'
        team1 = [pg["team1"]["player1"], pg["team1"]["player2"]]
        team2 = [pg["team2"]["player1"], pg["team2"]["player2"]]

        thisTeam = team1
        thisTeamScore = pg['team1']['score']
        otherTeamScore = pg['team2']['score']
        if playerName in team2
            thisTeam = team2
            thisTeamScore = pg['team2']['score']
            otherTeamScore = pg['team1']['score']

        if thisTeamScore > otherTeamScore
            score = process.env.WIN_EMOJI
            if otherTeamScore == 0
                score += process.env.SHUTOUT_EMOJI
            else if otherTeamScore == 8
                score += process.env.CLOSE_WIN_EMOJI

            score += '\t'
        else if thisTeamScore == 0
            score = process.env.NO_GOALS_EMOJI + '\t'
        else if thisTeamScore == 8
            score = process.env.CLOSE_LOSS_EMOJI + '\t'

        score += "#{thisTeamScore}-#{otherTeamScore}"

        if playerName == pg['team1']['player1']
            teams = [pg['team1']['player1'], pg['team1']['player2'], pg['team2']['player1'], pg['team2']['player2']]
        else if playerName == pg['team1']['player2']
            teams = [pg['team1']['player2'], pg['team1']['player1'], pg['team2']['player1'], pg['team2']['player2']]
        else if playerName == pg['team2']['player1']
            teams = [pg['team2']['player1'], pg['team2']['player2'], pg['team1']['player1'], pg['team1']['player2']]
        else
            teams = [pg['team2']['player2'], pg['team2']['player1'], pg['team1']['player1'], pg['team1']['player2']]

        strGames += "\n#{score}\t#{teams[0]} and #{teams[1]} vs. #{teams[2]} and #{teams[3]}"

    res.send strGames


totalGamesRespond = (res) ->
    res.send finishedGames.length


rematchRespond = (res) ->
    playerName = res.message.user.name.trim().toLowerCase()

    for i in [finishedGames.length-1..0] by -1
        fgame = finishedGames[i]
        fgamePlayers = [fgame["team1"]["player1"], fgame["team1"]["player2"], fgame["team2"]["player1"], fgame["team2"]["player2"]]

        if playerName in fgamePlayers
            res.send "Rematch called by #{playerName}!"
            startingPlayers = fgamePlayers.filter (name) -> name != playerName
            startGameRespond(res, startingPlayers)
            return

    res.send "Nothing to rematch, you haven't played any previous games"


module.exports = (robot) ->
    robot.respond /games/i, gamesRespond

    robot.respond /total games/i, totalGamesRespond

    robot.respond /find (?:people|players) for game (\d+)/i, findPeopleForGameRespond
    robot.respond /join game (\d+)/i, joinGameRespond
    robot.respond /add (\w+) to game (\d+)/i, addToGameRespond
    robot.respond /kick (\w+) from game (\d+)/i, kickFromGameRespond
    robot.respond /abandon game (\d+)/i, abandonGameRespond
    robot.respond /cancel game (\d+)/i, cancelGameRespond
    robot.respond /balance game (\d+)/i, balanceGameRespond
    robot.respond /shuffle game (\d+)/i, shuffleGameRespond

    robot.respond /start game$/i, startGameRespond
    robot.respond /start game(?: with)?(( \w+){1,3})$/i, startGameWithPlayersRespond
    robot.respond /find people|find players$/i, findPeopleForNextGameRespond
    robot.respond /i'm in/i, joinNextGameRespond
    robot.respond /join game$/i, joinNextGameRespond
    robot.respond /add (\w+)$/i, addToNextGameRespond
    robot.respond /kick (\w+)$/i, kickFromNextGameRespond
    robot.respond /abandon game$/i, abandonNextGameRespond
    robot.respond /cancel game$/i, cancelNextGameRespond
    robot.respond /balance game$/i, balanceNextGameRespond
    robot.respond /shuffle game$/i, shuffleNextGameRespond
    robot.respond /rematch/i, rematchRespond

    robot.respond /finish game +((\d-\d)( *, *\d-\d)*)$/i, finishGameRespond
    robot.respond /(rankings|leaderboard)$/i, rankingsRespond
    robot.respond /(?:stats|rankings)(( \w+)+)$/i, rankingsForPlayersRespond
    robot.respond /top (\d+).*$/i, topNRankingsRespond
    robot.respond /reset previous rankings$/i, resetPreviousRankings

    robot.respond /history (\w+)( \d+)?$/i, historyRespond
    robot.respond /team stats (\w+) (\w+)$/i, teamStatsRespond

    robot.respond /go on (a )?cleanse$/i, goOnACleanseRespond
    robot.respond /return from cleanse$/i, returnFromCleanseRespond

    robot.respond /the rules/i, theRulesRespond
