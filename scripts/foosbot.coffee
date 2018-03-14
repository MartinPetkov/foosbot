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
#   foosbot Call <player_name> - Call a player to join the next game
#   foosbot Kick <player_name> - Kick a player from the next game
#   foosbot Abandon game - Free up your spot in the next game
#   foosbot Cancel game - Cancel the next game
#   foosbot Balance game - Balance the next game based on player ranks
#   foosbot Shuffle game - Randomly shuffle the players in the next game
#   foosbot Find people|players for game <n> - Ask for people to play in the nth game
#   foosbot Join game <n> - Claim a spot in the nth game
#   foosbot Add <player_name> to game <n> - Add a player that may or may not be on LCB to the nth game
#   foosbot Call <player_name> to game <n> - Call a player to join the nth game
#   foosbot Kick <player_name> from game <n> - Kick a player from the nth game
#   foosbot Abandon game <n> - Free up your spot in the nth game
#   foosbot Cancel game <n> - Cancel the nth game
#   foosbot Balance game <n> - Balance the nth game based on player ranks
#   foosbot Shuffle game <n> - Randomly shuffle the players in the nth game
#   foosbot Finish game <team1_score>-<team2_score> - Finish the next game in order and record the results
#   foosbot Rematch - Repair your pride by playing the same game you just lost
#   foosbot Go on [a] cleanse - Go on a cleanse, unable to be added to a game
#   foosbot Return from cleanse - Return refreshed, ready to take on the champions
#   foosbot Retire - Hang up the gloves for good
#   foosbot Unretire - Rise up from the ashes of old age and get back to the table
#   foosbot Rankings|Leaderboard - Show the leaderboard
#   foosbot Rankings|Stats <player1> [<player2> ...] - Show the stats for specific players
#   foosbot Top <n> - Show the top n players in the rankings
#   foosbot History <player>|me [<numPastGames>|all] - Show a summary of your past games
#   foosbot Team history <player>|me <otherPlayer> [<numPastGames>|all] - Show a summary of past games with a specific teammate
#   foosbot Rival history <player>|me <otherPlayer> [<numPastGames>|all] - Show a summary of past games against a specific rival
#   foosbot Team Stats <playerOne>|me <playerTwo>|me|all - Shows the team stats for two players, or all pairings of <playerOne>
#   foosbot The rules - Show the rules we play by
#   foosbot Start tournament - Begin a new tournament (cannot run multiple tournaments at once)
#   foosbot Start tournament with <n> people - Begin a new tournament with some number of people (must be a power of 2)
#   foosbot Cancel tournament - Cancel the currently running tournament (nothing will get saved)
#   foosbot Show tournament - Show the current tournament tree
#   foosbot Show tournament players - Show all the players involved in the tournament
#   foosbot Show tournament teams - Show all the teams involved in the tournament
#   foosbot Swap tournament player <current_player> with <new_player> - Replace a player in the tournament (only works with players that had ranks when the tournament was started)
#   foosbot Accept tournament players - Confirm the player selection and officially begin the tournament
#   foosbot Finish tournament game round <n1> game <n2> <team1_score>-<team2_score> - Finish a game and have the team move on
#   foosbot Start betting - Join the betting pool
#   foosbot My balance - Ask for your current balance
#   foosbot Bet <x.y> on game <n> team (0|1) - Place a bet of <x.y>ƒ¢ (i.e. 5.2) on game <n> for team 0 or 1 (placing again replaces your previous bet)
#   foosbot All in on game <n> team (0|1) - Place a bet of all your money on game <n> for team 0 or 1 (placing again replaces your previous bet)
#   foosbot Cancel bet on game <n> - Withdraw your bet for game <n>
#   foosbot Tip - Get a helpful tip!
#   foosbot Store - See what you can buy with your hard-earned ƒ¢
#   foosbot Buy <good> [for <friend>] - Spend your hard-earned ƒ¢ on a good, possibly for a friend
#
# Author:
#   MartinPetkov

fs = require 'fs'
ts = require 'trueskill'
schedule = require 'node-schedule'
Influx = require('influx')

# Must be a power of 2
_DEFAULT_TOURNAMENT_SIZE = 16

_UNBALANCED_GAME_THRESHOLD = 10

# Betting constants
_STARTING_FOOSCOIN = 30.0
_HOUSE_PRIZE = 10.0

# Spending constants
_COST_OF_GOODS = {
    'meme': 20.0,
    'time meme': 30.0,
    'dad joke': 10.0,
    'xkcd': 30.0,
    'adviceanimal': 20.0,
    'aww': 20.0,
    'funny': 20.0,
    'whoa': 30.0,
    'reddit': 1000.0,
}


# Rules and tips
_THE_RULES = [
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
    "Everyone has 3 seconds after a drop to call a redrop",
    "If a player takes both hands off the handles and clearly stops playing, play is considered paused",
    "If you get shut out, you have to crawl under the table"
    "Everyone shakes hands at the end of the game, no exceptions",
]

tipsFileName = "tips.txt"
if !(fs.existsSync(tipsFileName))
    fs.closeSync(fs.openSync(tipsFileName, 'w'))
_TIPS = (fs.readFileSync tipsFileName, 'utf8').toString().split("\n").filter(Boolean)


gamesFile = 'games.json'
finishedGamesFile = 'finishedgames.json'
previousRanksFile = 'previousranks.json'
cleanseFile = 'cleanse.json'
retireesFile = 'retirees.json'
tournamentFile = 'tournament.json'
accountsFile = 'accounts.json'

loadFile = (fileName, initialValue) ->
    # Initialize the file if it does not exist
    if !(fs.existsSync(fileName))
        fs.writeFileSync(fileName, JSON.stringify(initialValue))

    return JSON.parse((fs.readFileSync fileName, 'utf8').toString().trim())

saveFile = (fileName, data) ->
    fs.writeFileSync(fileName, JSON.stringify(data))

games = loadFile(gamesFile, [])
finishedGames = loadFile(finishedGamesFile, [])
previousRanks = loadFile(previousRanksFile, {})
cleanse = loadFile(cleanseFile, [])
retirees = loadFile(retireesFile, [])
tournament = loadFile(tournamentFile, {'started': false, 'size': _DEFAULT_TOURNAMENT_SIZE})
accounts = loadFile(accountsFile, {})

saveGames = () ->
    saveFile(gamesFile, games)

saveFinishedGames = () ->
    saveFile(finishedGamesFile, finishedGames)

savePreviousRanks = () ->
    saveFile(previousRanksFile, previousRanks)

saveCleanse = () ->
    saveFile(cleanseFile, cleanse)

saveRetirees = () ->
    saveFile(retireesFile, retirees)

saveTournament = () ->
    saveFile(tournamentFile, tournament)

saveAccounts = () ->
  saveFile(accountsFile, accounts)


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
_MAXIMUM_SLACK_LEVEL = 10
getShameMsg = (res, player, timesPlayed) ->
    shameMsg = if timesPlayed >= _MAXIMUM_SLACK_LEVEL then _DEFAULT_SHAME_MESSAGE else res.random _SHAME_MESSAGES
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


isPowerOfTwo = (mynum) ->
    return (Math.log2(mynum) % 1) == 0


rightPad = (s, finalLength) ->
    numSpaces = Math.max(0, finalLength - s.length)
    return s + ' '.repeat(numSpaces)


customRound = (num, decimals) ->
    return Number(Math.round(num+'e'+decimals)+'e-'+decimals);


gamesRespond = (res) ->
    # List the games, in groups of 4, with the indices
    if games.length <= 0
        res.send "No games started"
        return

    responseLines = []
    for game, index in games
        gamePlayers = game['players']
        team1 = "#{gamePlayers[0]} and #{gamePlayers[1]}"
        team2 = "#{gamePlayers[2]} and #{gamePlayers[3]}"

        # Calculate bets for each team
        team1Bets = 0.0
        team2Bets = 0.0
        for betterName of game['bets']
            bet = game['bets'][betterName]
            if bet['team'] == 0
                team1Bets += bet['amount']
            else
                team2Bets += bet['amount']
        
        if team1Bets > 0
            team1 += " (#{team1Bets}ƒ¢ bet)"
        if team2Bets > 0
            team2 += " (#{team2Bets}ƒ¢ bet)"

        responseLines.push "Game #{index}:\n#{team1}\nvs.\n#{team2}\n"

    res.send responseLines.join('\n')


startGameRespond = (res, startingPlayers) ->
    # Create a new group of four, at the end of the games array
    captain = res.message.user.name
    if captain in cleanse
        res.reply "You can't start any games, you're on a cleanse!"
        return

    if captain in retirees
        res.reply "You can't start any games, you're retired!"
        return

    games.push {
        "players": [captain, '_', '_', '_'],
        "bets": {}
    }
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

    gamePlayers = games[n]['players']
    currentPlayers = (player for player in gamePlayers when player != "_")
    spotsLeft = 4 - currentPlayers.length
    if spotsLeft <= 0
        res.send "No spots left in #{gameStr}"
        return

    # Ask @all who's up for a game, and announce who's currently part of the nth game
    currentPlayers = currentPlayers.join(', ')

    res.send "@here Who's up for a game? #{gameStr} has #{spotsLeft} spots, current players are #{currentPlayers}"

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

getStats = (gamesToProcess) ->
    tmpGamesToProcess = if isUndefined(gamesToProcess) then finishedGames else gamesToProcess

    # Return stats for all players, which is a map from player name to object with games played, games won, and win percentage
    stats = {}
    for finishedGame in tmpGamesToProcess
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
        stats[player]['winPercentage'] = customRound((stats[player]['gamesWon'] / stats[player]['gamesPlayed']) * 100, 2)
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
    return "#{if winning then '🔥' else '💩'} #{gameStreak} #{if winning then 'won' else 'lost'}"

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

getRankings = (stats) ->
    # Get the stats for each player
    if isUndefined(stats)
        stats = getStats()

    # Remove all retirees
    for retiree in retirees
        if retiree of stats
            delete stats[retiree]

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
    responseList = new Array(rankings.length + 4).fill('') # Initialize with empty lines, to add to later
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

    responseList = ['```', responseList..., '```']
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


getChangedRankings = (res, rankings, p1, p2, p3, p4) ->
    rankChanges = "\nRank changes:\n"

    for p in [p1,p2,p3,p4]
        curRank = getRank(p, rankings) + 1
        if p of previousRanks
            prevRank = previousRanks[p]
            rankDiff = prevRank - curRank
            prefix = if rankDiff < 0 then '' else if rankDiff == 0 then '=' else '+'
        else
            rankDiff = curRank
            prefix = '~'

        rankChanges += "#{prefix}#{rankDiff} -> #{curRank} #{p}\n"

    resetPreviousRankings(res)

    return rankChanges


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

sendUnbalancedGameMsg = (res, p1, p2, rankDiff) ->
    res.send "WARNING! Unbalanced game! Rank difference between #{p1} and #{p2} in the game is #{rankDiff} (>#{_UNBALANCED_GAME_THRESHOLD})"

balancePlayers = (res, game) ->
    # Get the player rankings, which are sorted correctly
    rankings = getRankings()

    # Balance based on rank
    playersWithRanks = game.map (player) -> {"name": player, "rank": getRank(player, rankings)}
    playersWithRanks.sort(rankSort)

    # Send warning if rank difference is too great
    rankDifference = Math.abs(playersWithRanks[0]["rank"] - playersWithRanks[1]["rank"])
    if rankDifference > _UNBALANCED_GAME_THRESHOLD
        unbalancedPlayer1 = playersWithRanks[0]["name"]
        unbalancedPlayer2 = playersWithRanks[1]["name"]
        sendUnbalancedGameMsg(res, unbalancedPlayer1, unbalancedPlayer2, rankDifference)

    rankDifference = Math.abs(playersWithRanks[2]["rank"] - playersWithRanks[3]["rank"])
    if rankDifference > _UNBALANCED_GAME_THRESHOLD
        unbalancedPlayer1 = playersWithRanks[2]["name"]
        unbalancedPlayer2 = playersWithRanks[3]["name"]
        sendUnbalancedGameMsg(res, unbalancedPlayer1, unbalancedPlayer2, rankDifference)

    # Update the game
    game[0] = playersWithRanks[0]["name"]
    game[1] = playersWithRanks[3]["name"]
    game[2] = playersWithRanks[1]["name"]
    game[3] = playersWithRanks[2]["name"]

shufflePlayers = (n) ->
    # Simply rotate the last 3 players left
    game = games[n]["players"]
    games[n]["players"] = [game[0]].concat(game.slice(2).concat(game[1]))

joinGameRespond = (res, n, playerName) ->
    newPlayer = if isUndefined(playerName) then res.message.user.name else playerName
    if newPlayer in cleanse
        if isUndefined(playerName)
            res.reply "You can't join any games, you're on a cleanse!"
        else
            res.send "#{newPlayer} cannot join games, they are on a cleanse!"
        return

    if newPlayer in retirees
        if isUndefined(playerName)
            res.reply "You can't join any games, you're retired!"
        else
            res.send "#{newPlayer} cannot join games, they are retired!"
        return

    n = if isUndefined(n) then parseInt(res.match[1].trim(), 10) else n
    if isInvalidIndex(n)
        res.send "Invalid game index #{n}"
        return

    shameSlacker(res, newPlayer)

    gameStr = if n == 0 then "Next game" else "Game #{n}"

    gamePlayers = games[n]['players']
    if gamePlayers.indexOf(newPlayer) >= 0
        res.send "You're already part of that game!"
        return

    # Add yourself to the nth game
    for player, index in gamePlayers
        if player == '_'
            gamePlayers[index] = newPlayer
            res.send "#{newPlayer} joined #{gameStr}!"
            if gamePlayers.indexOf('_') < 0
                balancePlayers(res, gamePlayers)
                teamOneWinRate = getTeamStats(gamePlayers[0], gamePlayers[1])[gamePlayers[1]]["winPercentage"]
                teamTwoWinRate = getTeamStats(gamePlayers[2], gamePlayers[3])[gamePlayers[3]]["winPercentage"]

                teamsStr = "@#{gamePlayers[0]} and @#{gamePlayers[1]} (#{teamOneWinRate}%)\n"
                teamsStr += "vs.\n"
                teamsStr += "@#{gamePlayers[2]} and @#{gamePlayers[3]} (#{teamTwoWinRate}%)"
                res.send "#{gameStr} is ready to go! Teams:\n#{teamsStr}"

            saveGames()

            return

    # Cannot join if full
    res.send "No spots in #{gameStr}"


abandonGameRespond = (res, n, playerName) ->
    senderPlayer = if isUndefined(playerName) then res.message.user.name else playerName
    n = if isUndefined(n) then parseInt(res.match[1].trim(), 10) else n
    if isInvalidIndex(n)
        res.send "Invalid game index #{n}"
        return

    gamePlayers = games[n]['players']
    playerIndex = gamePlayers.indexOf(senderPlayer)
    if playerIndex < 0
        res.send "#{senderPlayer} is not part of Game #{n}"
        return

    # Return any bets placed on that game
    returnBets(res, n)

    gamePlayers[playerIndex] = '_'
    saveGames()

    # Abandon the nth game, freeing your spot in it
    remainingPlayers = [(player for player in gamePlayers when player != "_")].join(', ')
    res.send "#{senderPlayer} abandoned game #{n}. Remaining players: #{remainingPlayers}"

    gamesRespond(res)


cancelGameRespond = (res, n) ->
    n = if isUndefined(n) then parseInt(res.match[1].trim(), 10) else n
    if isInvalidIndex(n)
        res.send "Invalid game index #{n}"
        return

    # Return any bets placed on that game
    returnBets(res, n)

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


callToGameRespond = (res, n) ->
    # Add a player to the nth game
    playerName = res.match[1].trim()
    n = if isUndefined(n) then parseInt(res.match[2].trim(), 10) else n

    if isInvalidIndex(n)
        res.send "Invalid game index #{n}"
        return

    gameStr = if n == 0 then "the next game" else "game #{n}"

    gamePlayers = (player for player in games[n]['players'] when player != "_")

    if gamePlayers.length >= 4
        res.send "Game is full!"
        return

    if playerName in gamePlayers
        res.send "#{playerName} is already part of #{gameStr}!"
        return

    gamePlayers = gamePlayers.join(', ')
    if gamePlayers.length <= 0
        gamePlayers = 'yourself'

    res.send "@#{playerName} come play with #{gamePlayers} in #{gameStr}!"

callToNextGameRespond = (res) ->
    # Add yourself to the next game
    # Cannot join if full
    callToGameRespond(res, 0)


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

    balancePlayers(res, games[n]['players'])
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

    shufflePlayers(n)
    returnBets(res, n)
    saveGames()
    gamesRespond(res)

    res.send "Game #{n} shuffled"

shuffleNextGameRespond = (res) ->
    shuffleGameRespond(res, 0)


letsGoRespond = (res) ->
    if games.length <= 0
        res.send "No games are being played at the moment"
        return

    senderName = res.message.user.name
    playersStr = games[0]['players'].filter((name) -> name != senderName && name != '_').map((p) -> "@#{p}").join(' ')
    res.send "#{playersStr} let's go"


sendStatsToInfluxDB = (newRankings, res, timestamp) ->
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0'

    # Allow errors to happen, it's not a big deal if stats don't get sent out
    try
        influx = new Influx.InfluxDB({
            host: process.env.INFLUX_DB_HOST,
            port: process.env.INFLUX_DB_PORT,
            database: process.env.INFLUX_DB_DATABASE,
            username: process.env.INFLUX_DB_USERNAME,
            password: process.env.INFLUX_DB_PASSWORD,
            protocol: 'https',
        });

        for player of newRankings
            point = {
                measurement: "foosballRankings",
                tags: { 'name': "#{newRankings[player]['name']}" }
                fields: newRankings[player],
            }

            # Possibly add a custom timestamp (i.e. when recreating old games)
            if !(isUndefined(timestamp))
                point['timestamp'] = timestamp

            # This field is an array
            # InfluxDB has never heard of arrays and panics when it sees one
            delete point['fields']['skill']

            # Grafana has very weak post-processing capabilities, so just
            # give it the emoji-formatted streak string to begin with
            point['fields']['streak'] = streakFormat(point['fields']['streak'])

            # InfluxDB also can't accept multiple points per measurement 
            influx.writePoints([point])

    catch err
        msg = "Failed to upload stats to InfluxDB! Error:\n#{err}"
        
        if isUndefined(res)
            console.log(msg)
        else
            res.send msg

    process.env.NODE_TLS_REJECT_UNAUTHORIZED = '1'


uploadOldRankings = (res) ->
    numFinishedGames = finishedGames.length
    for v, i in finishedGames
        oldStats = getStats(finishedGames[..i])
        oldRankings = getRankings(oldStats)

        # Have to fake the times, since they don't get tracked
        fakeTimestamp = new Date()
        fakeTimestamp.setHours(fakeTimestamp.getHours() - (5 * (numFinishedGames - i - 1)))
        console.log(fakeTimestamp.toLocaleString())

        sendStatsToInfluxDB(oldRankings, undefined, fakeTimestamp)

    res.send('Old rankings uploaded')

finishGameRespond = (res) ->
    if games.length <= 0
        res.send "No games are being played at the moment"
        return

    game = games[0]
    gamePlayers = game['players']
    if gamePlayers.indexOf('_') >= 0
        res.send "Next game isn't ready to go yet!"
        return

    result = res.match[1].trim().split('-')
    t1score = parseInt(result[0], 10)
    t2score = parseInt(result[1], 10)

    t1p1 = gamePlayers[0].trim().toLowerCase()
    t1p2 = gamePlayers[1].trim().toLowerCase()
    t2p1 = gamePlayers[2].trim().toLowerCase()
    t2p2 = gamePlayers[3].trim().toLowerCase()

    oldStats = getStats()
    oldRankings = getRankings(oldStats)
    oldNumberOne = oldRankings[0]

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

        if !(player of oldStats)
            oldStats[player] = {
                'trueskill': 0.0
            }

    # Record the scores and save them
    finishedGames.push resultDetails

    finishedGamesMsg = ["Results saved\n"]

    # Return the bets to the bet winners
    winningTeam = if t1score > t2score then 0 else 1
    betWinners = []
    betWinnersTotalPool = 0
    prizePool = 0
    for betterName of game['bets']
        if game['bets'][betterName]['team'] == winningTeam
            betWinnersTotalPool += game['bets'][betterName]['amount']
            # Return the winner's bet, but don't announce it
            accounts[betterName] += game['bets'][betterName]['amount']
            betWinners.push(betterName)
        else
            prizePool += game['bets'][betterName]['amount']

    # Give extra money from the house, based on trueskill
    winningTeamPlayers = if t1score > t2score then [t1p1,t1p2] else [t2p1,t2p2]
    losingTeamPlayers = if t1score > t2score then [t2p1,t2p2] else [t1p1,t1p2]
    housePrizeProportion = 1.5

    if (t1p1 of oldStats) && (t1p2 of oldStats) && (t2p1 of oldStats) && (t2p2 of oldStats)
        winningTeamTrueskill = oldStats[losingTeamPlayers[0]]['trueskill'] + oldStats[losingTeamPlayers[1]]['trueskill']
        losingTeamTrueskill = oldStats[winningTeamPlayers[0]]['trueskill'] + oldStats[winningTeamPlayers[1]]['trueskill']
        if (winningTeamTrueskill > 0) && (losingTeamTrueskill > 0)
            housePrizeProportion = housePrizeProportion * (winningTeamTrueskill / losingTeamTrueskill)

    if betWinners.length > 0
        for betWinner in betWinners
            if betWinner of accounts
                # Award the house prize
                # housePrize = housePrizeProportion * game['bets'][betWinner]['amount']
                # housePrize = housePrizeProportion * _HOUSE_PRIZE
                housePrize = housePrizeProportion * Math.max(_HOUSE_PRIZE, 5 * Math.sqrt(game['bets'][betWinner]['amount']))
                accounts[betWinner] += housePrize
                finishedGamesMsg.push("@#{betWinner} won #{housePrize}ƒ¢ from the house!")

                # Distribute the prize pool from the losers
                if prizePool > 0
                    # Determine how much this winner should get, proportional to what they bet
                    proportion = customRound(game['bets'][betWinner]['amount'] / betWinnersTotalPool, 4)
                    betWinAmount = customRound(prizePool * proportion, 4)

                    accounts[betWinner] += betWinAmount
                    finishedGamesMsg.push("@#{betWinner} won #{betWinAmount}ƒ¢ from betting!")

    # Award a prize to the winners of the match, equal to the number of goals scored
    matchWinners = if t1score > t2score then [t1p1,t1p2] else [t2p1,t2p2]
    matchWinnersScore = if t1score > t2score then t1score else t2score
    matchLosersScore = if t1score > t2score then t2score else t1score

    goalDifference = Math.abs(t1score - t2score)
    matchWinAmount = if goalDifference == 1 or matchLosersScore == 0 then 20 else 1 + (2 * (9 - goalDifference))

    # Give more if the trueskill difference is larger
    matchWinAmount += housePrizeProportion * matchWinAmount

    # Determine how much of the opposing prize pool to give, with the goals as a percentage
    if prizePool > 0
        matchWinAmount += prizePool * (matchWinnersScore / 100.0)

    # Add pity prize for scoring on the #1
    if !(isUndefined(oldNumberOne))
        if oldNumberOne.name in matchWinners
            for matchLoser in losingTeamPlayers
                if matchLoser of accounts
                    accounts[matchLoser] += 1
                    finishedGamesMsg.push("@#{matchLoser} won 1ƒ¢ for scoring on the #1, #{oldNumberOne.name}!")

    # Double the win amount in case of a shutout
    if matchLosersScore == 0
        matchWinAmount = matchWinAmount * 2
        finishedGamesMsg.push("Double fooscoins for a shutout win!")

    for matchWinner in matchWinners
        if matchWinner of accounts
            accounts[matchWinner] += matchWinAmount
            finishedGamesMsg.push("@#{matchWinner} won #{matchWinAmount}ƒ¢!")


    # Remove the game from the list
    games.splice(0,1)

    # Save the variables
    saveAccounts()
    saveFinishedGames()
    saveGames()

    # Get the new rankings
    newRankings = getRankings()

    # Send data to influxdb if configured
    if process.env.INFLUX_DB_ENABLED == 'Y'
        sendStatsToInfluxDB(newRankings, res)

    # Show changed rankings since last time
    finishedGamesMsg.push(getChangedRankings(res, newRankings, t1p1, t1p2, t2p1, t2p2))

    # Send the message
    res.send finishedGamesMsg.join('\n')

    # Shame those that got shut out
    if matchLosersScore == 0
        res.send "https://media.giphy.com/media/gtakVlnStZUbe/giphy.gif"

theRulesRespond = (res) ->
    res.send _THE_RULES.map((rule, i) -> "#{i+1}. #{rule}").join('\n')

tipRespond = (res) ->
    res.send res.random _TIPS


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


historyMeRespond = (res) ->
    me = res.match[1] == 'me'
    playerName = if me then res.message.user.name else res.match[1].trim().toLowerCase()
    numPastGames = if isUndefined(res.match[2]) then 5 else res.match[2].trim()

    historyRespond(res, me, numPastGames, playerName)

multiHistoryRespond = (res, rivals) ->
    me = res.match[1] == 'me'
    playerName = if me then res.message.user.name else res.match[1].trim().toLowerCase()
    otherPlayerName = res.match[2].trim().toLowerCase()
    numPastGames = if isUndefined(res.match[3]) then 5 else res.match[3].trim()

    historyRespond(res, me, numPastGames, playerName, otherPlayerName, rivals)

teamHistoryRespond = (res) ->
    multiHistoryRespond(res, false)

rivalHistoryRespond = (res) ->
    multiHistoryRespond(res, true)


historyRespond = (res, me, numPastGames, playerName, otherPlayerName, rivals) ->
    gamesFound = 0
    pastGames = []

    if !(numPastGames == 'all')
        numPastGames = parseInt(numPastGames, 10)

    # Collect the last n games
    for i in [finishedGames.length-1..0] by -1
        fgame = finishedGames[i]

        fgPlayers = [fgame["team1"]["player1"], fgame["team1"]["player2"], fgame["team2"]["player1"], fgame["team2"]["player2"]]
        keepGame = false
        if isUndefined(otherPlayerName)
            # Single-player history
            if playerName in fgPlayers
                keepGame = true
        else
            # Team history
            fgTeam1 = [fgame["team1"]["player1"], fgame["team1"]["player2"]]
            fgTeam2 = [fgame["team2"]["player1"], fgame["team2"]["player2"]]

            if rivals
                keepGame = ((playerName in fgTeam1) && (otherPlayerName in fgTeam2)) || ((playerName in fgTeam2) && (otherPlayerName in fgTeam1))
            else
                keepGame = ((playerName in fgTeam1) && (otherPlayerName in fgTeam1)) || ((playerName in fgTeam2) && (otherPlayerName in fgTeam2))

        if keepGame
            pastGames.unshift(fgame)
            gamesFound += 1

            if numPastGames != 'all' && gamesFound >= numPastGames
                break


    pronoun = "#{playerName}'s"
    together = ""
    if !(isUndefined(otherPlayerName))
        pronoun = "#{playerName} and #{otherPlayerName}'s"
        together = if rivals then " against each other" else " together"


    gamesWon = 0
    title = "#{pronoun} last #{numPastGames} games#{together}:"
    strGames = ""
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
            gamesWon += 1
            score = process.env.WIN_EMOJI
            if otherTeamScore == 0
                score += process.env.SHUTOUT_EMOJI
            else if otherTeamScore == 8
                score += process.env.CLOSE_WIN_EMOJI
            else
                score += '\t'

        else if thisTeamScore == 0
            score = process.env.NO_GOALS_EMOJI
        else if thisTeamScore == 8
            score = process.env.CLOSE_LOSS_EMOJI
        else
            score += '\t'
        
        score += '\t'

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

    strGames = title + "\nK-D ratio: #{gamesWon}-#{gamesFound-gamesWon}\n" + strGames

    strGames = '```' + strGames + '```'

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


# Tournament responders
startTournamentWithNPeopleRespond = (res) ->
    tournamentSize = parseInt(res.match[1].trim(), 10)

    if !isPowerOfTwo(tournamentSize)
        res.send "The number of must be a power of 2, and #{tournamentSize} is not!"
        return

    if tournamentSize < 4
        res.send "You need at least 4 people to start a tournament!"
        return

    tournament['size'] = tournamentSize
    startTournamentRespond(res)

startTournamentRespond = (res) ->
    # Initialize the game with the top 16 players
    # Save all players and their ranks at that time
    # Create teams by pairing 1-16, 2-15, etc.
    if tournament['started']
        res.send 'Tournament has already been started! Please cancel the current one if you wish to start a new one.'
        return

    tournament = {
        'allPlayers': [],
        'tournamentPlayers': [],
        'tournamentTeams': [],
        'allGames': [],
        'accepted': false,
        'started': true,
        'size': tournament['size'],
    }

    # Get all players
    tournament['allPlayers'] = getRankings()

    if tournament['allPlayers'].length < tournament['size']
        res.send "Not enough players to start tournament. Have: #{tournament['allPlayers'].length}; Need: #{tournament['size']}"
        return

    # Choose the top tournament['size'] players to participate
    tournament['tournamentPlayers'] = tournament['allPlayers'].slice(0, tournament['size'])

    prepareAndDistributeTournamentTeams()

    saveTournament()

    res.send 'Tournament started!'

    showTournamentRespond(res)


prepareTournamentGames = () ->
    # Clear the games
    tournament['allGames'] = []

    # Prepare games with log_2(tournament['size']/2) rounds
    numRounds = Math.log2(tournament['size']/2)

    for r in [numRounds-1..0] by -1
        firstRound = false
        if tournament['allGames'].length <= 0
            firstRound = true

        topTeam = true

        gameRound = []
        numGamesInRound = Math.pow(2, r)
        for g in [0..numGamesInRound-1]
            previousGames = false
            if !firstRound
                previousGames = [(2 * g), (2 * g) + 1]

            nextGame = if numGamesInRound == 1 then false else Math.floor(g/2)

            gameRound.push {
                'previousGames': previousGames,
                'nextGame': nextGame,
                'team1': false,
                'team2': false,
                'finalScore': false,
                'finished': false,
                'topTeam': topTeam,
            }

            # Make sure teams display correctly
            topTeam = !topTeam

        tournament['allGames'].push gameRound

prepareAndDistributeTournamentTeams = () ->
    # Prepare the games first
    prepareTournamentGames()

    # Make teams by pairing 1-16, 2-15, etc.
    for i in [0..(tournament['size']/2)-1]
        tournament['tournamentTeams'][i] = [
            tournament['tournamentPlayers'][i]['name'],
            tournament['tournamentPlayers'][tournament['size'] - 1 - i]['name'],
        ]

    # Populate the first round with players, alternating between placing at the top or bottom of the bracket
    i = 0
    teamsDistributed = 0
    bracketSideTop = true
    for team in tournament['tournamentTeams']
        if bracketSideTop
            game = tournament['allGames'][0][i]
        else
            game = tournament['allGames'][0][tournament['allGames'][0].length - 1 - i]

        if !game['team1']
            game['team1'] = team
        else
            game['team2'] = team

        teamsDistributed += 1
        if teamsDistributed == 4
            teamsDistributed = 0
            i += 1

        bracketSideTop = !bracketSideTop

cancelTournamentRespond = (res) ->
    if !tournament['started']
        res.send 'Tournament not started yet!'
        return

    # Empty out the object containing the tournament info
    tournament = {'started': false, 'size': _DEFAULT_TOURNAMENT_SIZE}
    saveTournament()

    res.send "Tournament cancelled"

showTournamentRespond = (res) ->
    if !tournament['started']
        res.send 'Tournament not started yet!'
        return

    # Print the tournament tree, in the following format
    # -------------|
    # goofy, daffy |
    #              |
    #         [9-1]|--------------|
    #              | goofy, daffy |
    # mick, minnie |              |
    # -------------|              |
    #                        [9-3]|--- goofy, daffy
    # -------------|              |
    # pluto, don   |              |
    #              | pluto, don   |
    #         [2-9]|--------------|
    #              |
    # noob, mike   |
    # -------------|

    startingLine = 0
    width = 6
    betweenGamesWidth = 2

    numStartingGames = tournament['allGames'][0].length
    numLines = (numStartingGames * width) + ((numStartingGames - 1) * betweenGamesWidth)

    # Add one "column" for each round
    strTree = new Array(numLines + 2).fill('') # Initialize with empty lines, to add to later
    for gameRound in tournament['allGames']
        longestLineLength = 7
        for game in gameRound
            if game['team1']
                longestLineLength = Math.max(longestLineLength, "#{game['team1']}".length + 7)
            if game['team2']
                longestLineLength = Math.max(longestLineLength, "#{game['team2']}".length + 7)

        # Draw each of the games
        numGames = gameRound.length
        currentLine = startingLine
        for i in [0..numGames-1]
            game = gameRound[i]
            gameStartingLine = currentLine

            # Draw the two lines on the top and bottom of the game
            strTree[currentLine] += '-'.repeat(longestLineLength)
            currentLine += width
            strTree[currentLine] += '-'.repeat(longestLineLength)

            # Draw the team names in the
            currentLine = gameStartingLine + 1
            if game['team1']
                teamStr = " #{game['team1']}"
                strTree[currentLine] += teamStr + ' '.repeat(longestLineLength - teamStr.length)
            currentLine += width - 2
            if game['team2']
                teamStr = " #{game['team2']}"
                strTree[currentLine] += teamStr + ' '.repeat(longestLineLength - teamStr.length)

            # Draw the score in the middle
            currentLine = gameStartingLine
            currentLine += (width/2)
            score = if game['finalScore'] then game['finalScore'] else '?-?'
            score = "[#{score}]"
            strTree[currentLine] += ' '.repeat(longestLineLength - score.length)
            strTree[currentLine] += score

            # Add the vertical lines
            currentLine = gameStartingLine
            while currentLine <= gameStartingLine+width
                if !(/(]|-|\w)$/.test(strTree[currentLine].trim()))
                    strTree[currentLine] += ' '.repeat(longestLineLength)

                strTree[currentLine] += '|'

                currentLine += 1

            if i < (numGames - 1)
                endLine = (currentLine + betweenGamesWidth - 1)
                while currentLine < endLine
                    strTree[currentLine] += ' '.repeat(longestLineLength+1)
                    currentLine += 1

        # Update where to start drawing the next round
        startingLine = startingLine + (width/2)
        width += betweenGamesWidth
        betweenGamesWidth = width

    # Draw the final winner line
    winrar = '?'
    finalGame = tournament['allGames'][tournament['allGames'].length-1][0]
    if finalGame['finished']
        score = finalGame['finalScore'].split('-')
        t1score = parseInt(score[0], 10)
        t2score = parseInt(score[1], 10)
        if t1score > t2score
            winrar = "#{finalGame['team1']}"
        else
            winrar = "#{finalGame['team2']}"

    strTree[startingLine] += "--- 🏆 #{winrar}"

    res.send strTree.join('\n')

showTournamentPlayersRespond = (res) ->
    if !tournament['started']
        res.send 'Tournament not started yet!'
        return

    # List all the players currently in the tournament and their ranks at the time of joining
    strPlayers = ['Rank:\tName:']
    for player in tournament['tournamentPlayers']
        strPlayers.push "#{player.rank}\t#{player.name}"

    res.send strPlayers.join('\n')

showTournamentTeamsRespond = (res) ->
    if !tournament['started']
        res.send 'Tournament not started yet!'
        return

    # List all the teams currently in the tournament
    strTeams = []
    for t, i in tournament['tournamentTeams']
        strTeams.push "Team #{i}:\n#{t[0]}, #{t[1]}"

    res.send strTeams.join('\n\n')

swapTournamentPlayersRespond = (res) ->
    if !tournament['started']
        res.send 'Tournament not started yet!'
        return

    # Try to swap two players

    # If players have been accepted, error out
    if tournament['playersAccepted']
        res.send 'Tournament players have been accepted, you can\'t make modifications anymore!'
        return

    p1Name = res.match[1].trim().toLowerCase()
    p2Name = res.match[2].trim().toLowerCase()

    # If the second player didn't exist when the tournament was started, error out
    p2 = false
    for p in tournament['allPlayers']
        if p['name'] == p2Name
            p2 = p
            break

    if !p2
        res.send "Player \"#{p2Name}\" did not exist when the tournament was started!"
        return

    # If the first player isn't in the tournament, error out
    p1Index = false
    for i in [0..tournament['tournamentPlayers'].length-1]
        if tournament['tournamentPlayers'][i]['name'] == p1Name
            p1Index = i

        # If the second player is already in the tournament, error out
        if tournament['tournamentPlayers'][i]['name'] == p2Name
            res.send "Player \"#{p2Name}\" is already in the tournament!"
            return

    if !p1Index
        res.send "Player \"#{p1Name}\" is not in the tournament!"
        return

    tournament['tournamentPlayers'][p1Index] = p2

    # Sort the players by the new rank
    tournament['tournamentPlayers'] = tournament['tournamentPlayers'].sort(rankSort)

    prepareAndDistributeTournamentTeams()

    saveTournament()

    res.send "Successfully swapped \"#{p1Name}\" with \"#{p2Name}\". Teams have been rebalanced."

acceptTournamentPlayersRespond = (res) ->
    if !tournament['started']
        res.send 'Tournament not started yet!'
        return

    # Freeze the players
    tournament['playersAccepted'] = true
    saveTournament()

    res.send 'Players accepted, tournament is ready to go!'

isInvalidGenericIndex = (genericIndex, maxLength) ->
    return isNaN(genericIndex) || genericIndex < 0 || genericIndex >= maxLength

finishTournamentGameRespond = (res) ->
    if !tournament['started']
        res.send 'Tournament not started yet!'
        return

    roundNum = parseInt(res.match[1].trim(), 10)
    gameNum = parseInt(res.match[2].trim(), 10)
    score = res.match[3].trim().split('-')
    t1score = parseInt(score[0], 10)
    t2score = parseInt(score[1], 10)

    # Finish a game, as indicated in the tree diagram
    # If players have not been accepted, error out
    if !tournament['playersAccepted']
        res.send 'Tournament players have not been accepted yet!'
        return

    # If the game does not exist, error out
    if isInvalidGenericIndex(roundNum, tournament['allGames'].length)
        res.send "Invalid round #{roundNum}"
        return

    gameRound = tournament['allGames'][roundNum]
    if isInvalidGenericIndex(gameNum, gameRound.length)
        res.send "Invalid game #{gameNum} in round #{roundNum}"
        return

    game = gameRound[gameNum]

    # If the game does not have both teams yet, error out
    if !game['team1'] || !game['team2']
        res.send "Game #{gameNum} in round #{roundNum} isn't ready to go yet!"
        return

    # If the game has been finished already, error out
    if game['finished']
        res.send "Game #{gameNum} in round #{roundNum} has already finished!"
        return

    # If the game is even, error out
    if t1score == t2score
        res.send "Cannot finish a tournament game with an even score, someone must lose"
        return

    # Finish the game and record the score
    game['finished'] = true
    game['finalScore'] = "#{t1score}-#{t2score}"

    # Determine the winner
    winrar = game['team2']
    losar = game['team1']
    strScore = "#{t2score}-#{t1score}"
    if t1score > t2score
        winrar = game['team1']
        losar = game['team2']
        strScore = "#{t1score}-#{t2score}"


    if game['nextGame'] == false
        # If the game finished is the final game, print out a congratulatory message and fanfare, crowning the champions
        res.send "Tournament is over! Congratulations to the champions!"
        res.send "🏆🏆🏆 #{winrar} 🏆🏆🏆"

    else
        # Add the team to the next game
        nextGame = tournament['allGames'][roundNum+1][game['nextGame']]
        if game['topTeam']
            nextGame['team1'] = winrar
        else
            nextGame['team2'] = winrar

        res.send "Finished game #{gameNum} in round #{roundNum}! #{winrar} beat #{losar} with a score of #{strScore}"

        showTournamentRespond(res)

    saveTournament()


retireRespond = (res) ->
    retiree = res.message.user.name.trim().toLowerCase()

    if retiree in retirees
        res.send "You've already retired, you can't double retire!"
        return

    retirees.push retiree

    saveRetirees()

    res.send "#{retiree} has permanently retired!"


unretireRespond = (res) ->
    retiree = res.message.user.name.trim().toLowerCase()

    if !(retiree in retirees)
        res.send "You're still kicking"
        return

    retirees.splice(retirees.indexOf(retiree), 1)

    saveRetirees()

    res.send "#{retiree} is back in the action!"


# Betting commands
startBettingRespond = (res) ->
    highRoller = res.message.user.name.trim().toLowerCase()

    if highRoller of accounts
        res.send "You have already bought in, you can't buy in again"
        return

    accounts[highRoller] = _STARTING_FOOSCOIN

    saveAccounts()

    res.send "#{highRoller} bought in! They start with #{_STARTING_FOOSCOIN}ƒ¢"
    
    
myBalanceRespond = (res) ->
    me = res.message.user.name.trim().toLowerCase()

    # Error out if person has not bought in yet
    if !(me of accounts)
        res.send 'You have not bought in yet!'
        return
    
    balance = customRound(accounts[me], 4)

    res.send "@#{me}, you have #{balance}ƒ¢"

placeBetRespond = (res, better, betAmount, n, teamToBetOn) ->
    if isInvalidIndex(n)
        res.send "Invalid game index #{n}"
        return

    game = games[n]

    if game['players'].indexOf(better) >= 0
        res.send "You can't bet on a game you're playing in!"
        return

    if !(better of accounts)
        res.send "You have not bought in yet!"
        return

    # Temporarily bring back the previous bet, then restore it if there are insufficient funds
    currentBetAmount = if better of game['bets'] then game['bets'][better]['amount'] else 0
    accounts[better] += currentBetAmount
    if accounts[better] < betAmount
        accounts[better] -= currentBetAmount
        res.send "You can't bet #{betAmount}ƒ¢, you only have #{accounts[better]}ƒ¢!"
        return

    # Place the bet, taking it out of the better's account
    accounts[better] -= betAmount
    game['bets'][better] = {
        'amount': betAmount,
        'team': teamToBetOn
    }

    sliceIndex = teamToBetOn * 2
    teamMembers = game['players'].slice(sliceIndex, sliceIndex + 2)

    saveAccounts()
    saveGames()

    res.send "#{better} bet #{betAmount}ƒ¢ on game #{n} for #{teamMembers}! They have #{accounts[better]}ƒ¢ left"

betRespond = (res) ->
    better = res.message.user.name.trim().toLowerCase()
    betAmount = parseFloat(res.match[1].trim(), 10)
    n = parseInt(res.match[2].trim(), 10)
    teamToBetOn = parseInt(res.match[3].trim(), 10)

    placeBetRespond(res, better, betAmount, n, teamToBetOn)

allInRespond = (res) ->
    better = res.message.user.name.trim().toLowerCase()
    if !(better of accounts)
        res.send "You have not bought in yet!"
        return

    betAmount = accounts[better]
    n = parseInt(res.match[1].trim(), 10)
    teamToBetOn = parseInt(res.match[2].trim(), 10)

    placeBetRespond(res, better, betAmount, n, teamToBetOn)
    
cancelBetRespond = (res) ->
    better = res.message.user.name.trim().toLowerCase()
    n = parseInt(res.match[1].trim(), 10)

    if isInvalidIndex(n)
        res.send "Invalid game index #{n}"
        return

    game = games[n]

    if !(better of game['bets'])
        res.send "You have not placed a bet on game #{n}"
        return

    if !(better of accounts)
        res.send "You couldn't have place a bet on game #{n}, you haven't bought in yet!"
        return

    accounts[better] += game['bets'][better]['amount']
    delete game['bets'][better]

    saveAccounts()
    saveGames()

    res.send "#{better} cancelled bet on game #{n}, they have #{accounts[better]}ƒ¢ left"

returnBets = (res, n) ->
    game = games[n]

    if Object.keys(game['bets']).length < 1
        return

    for betterName of game['bets']
        if betterName of accounts
            accounts[betterName] += game['bets'][betterName]['amount']

            res.send "#{betterName} got #{game['bets'][betterName]['amount']}ƒ¢ back, they have #{accounts[betterName]}ƒ¢ left"
    
    game['bets'] = {}

    saveAccounts()
    saveGames()

    res.send "All bets returned for game #{n}"


tipOfTheDaySend = (robot) ->
    return () ->
        topd = 'Here is your Tip Of The Day™!\n\n'
        randomTip = _TIPS[Math.round(Math.random() * (_TIPS.length - 1))]
        topd += randomTip

        robot.send room: process.env.FOOSBALL_ROOM_ID, topd


# Spending commands
storeRespond = (res) ->
    response = 'Store:\n'
    for good in Object.keys(_COST_OF_GOODS)
        response += "#{good}: #{_COST_OF_GOODS[good]}ƒ¢\n"

    res.send response

buyRespond = (robot) ->
    return (res) ->
        buyer = res.message.user.name.trim().toLowerCase()
        recipient = buyer

        # Determine the good being bought
        good = res.match[1]

        # Could be bought for someone else
        if !(isUndefined(res.match[2]))
            recipient = res.match[2].trim().toLowerCase()

        recipient = recipient.replace('@', '')

        if !(buyer of accounts)
            res.send "You have not bought in yet!"
            return

        balance = accounts[buyer]
        cost = _COST_OF_GOODS[good]

        if balance < cost
            res.send "You do not have enough ƒ¢ to buy a #{good}! You need #{cost}ƒ¢, you have #{balance}ƒ¢"
            return

        if good == 'meme'
            buyFromReddit(robot, res, 'memes')
        else if good == 'time meme'
            buyFromReddit(robot, res, 'trippinthroughtime')
        else if good == 'dad joke'
            buyDadJoke(robot, res)
        else if good == 'xkcd'
            buyxkcd(robot, res)
        else if good == 'adviceanimal'
            buyFromReddit(robot, res, 'AdviceAnimals')
        else if good == 'aww'
            buyFromReddit(robot, res, 'aww')
        else if good == 'funny'
            buyFromReddit(robot, res, 'funny')
        else if good == 'whoa'
            buyFromReddit(robot, res, 'woahdude')
        else if good == 'reddit'
            buyFromReddit(robot, res, res.match[2])
        else
            res.send "Out of stock on #{good}s"
            return

        accounts[buyer] -= cost

        saveAccounts()

        res.send "You bought a #{good} for #{cost}ƒ¢! Your balance is now: #{accounts[buyer]}ƒ¢"

        res.send "Here is your #{good}, @#{recipient}..."


buyFromReddit = (robot, res, subreddit) ->
    robot.http("https://www.reddit.com/r/#{subreddit}/top.json?count=100")
        .header('Accept', 'application/json')
        .get() (err, response, body) ->
            memes = JSON.parse(body)['data']
            memes = memes['children']

            # Keep going until we find a post that's an image
            while true
                memeIndex = Math.round(Math.random() * (memes.length - 1))
                randomMeme = memes[memeIndex]['data']
                link = randomMeme['url']

                if /(jpg|png|gif)$/.test(link)
                    break

            res.send link

buyDadJoke = (robot, res) ->
    robot.http('https://icanhazdadjoke.com/')
        .header('Accept', 'text/plain')
        .get() (err, response, body) ->
            res.send body

buyxkcd = (robot, res) ->
    # Get the latest comic so we know how many there are total
    robot.http('https://xkcd.com/info.0.json')
        .header('Accept', 'application/json')
        .get() (err, response, body) ->
            latest = parseInt(JSON.parse(body)['num'], 10)
            randomComicNumber = Math.round(Math.random() * latest) + 1

            # Get the actual comic
            robot.http("https://xkcd.com/#{randomComicNumber}/info.0.json")
                .header('Accept', 'application/json')
                .get() (err, response, body) ->
                    comic = JSON.parse(body)
                    res.send comic['img']
                    res.send "\"#{comic['alt']}\""


module.exports = (robot) ->
    robot.respond /games/i, gamesRespond

    robot.respond /total games/i, totalGamesRespond

    robot.respond /find (?:people|players) for game (\d+)/i, findPeopleForGameRespond
    robot.respond /join game (\d+)/i, joinGameRespond
    robot.respond /add (\w+) to game (\d+)/i, addToGameRespond
    robot.respond /call (\w+) to game (\d+)/i, callToGameRespond
    robot.respond /kick (\w+) from game (\d+)/i, kickFromGameRespond
    robot.respond /abandon game (\d+)/i, abandonGameRespond
    robot.respond /cancel game (\d+)/i, cancelGameRespond
    robot.respond /balance game (\d+)/i, balanceGameRespond
    robot.respond /shuffle game (\d+)/i, shuffleGameRespond

    robot.respond /start game$/i, startGameRespond
    robot.respond /start game(?: with)?(( \w+){1,3})$/i, startGameWithPlayersRespond
    robot.respond /find people$|find players$/i, findPeopleForNextGameRespond
    robot.respond /i.?m in/i, joinNextGameRespond
    robot.respond /join game$/i, joinNextGameRespond
    robot.respond /add (\w+)$/i, addToNextGameRespond
    robot.respond /call (\w+)$/i, callToNextGameRespond
    robot.respond /kick (\w+)$/i, kickFromNextGameRespond
    robot.respond /abandon game$/i, abandonNextGameRespond
    robot.respond /cancel game$/i, cancelNextGameRespond
    robot.respond /balance game$/i, balanceNextGameRespond
    robot.respond /shuffle game$/i, shuffleNextGameRespond
    robot.respond /rematch/i, rematchRespond

    robot.hear /^(let's +)?go$/i, letsGoRespond
    robot.respond /finish game +(\d-\d)$/i, finishGameRespond
    robot.respond /(rankings|leaderboard)$/i, rankingsRespond
    robot.respond /(?:stats|rankings)(( \w+)+)$/i, rankingsForPlayersRespond
    robot.respond /top (\d+).*$/i, topNRankingsRespond
    robot.respond /reset previous rankings$/i, resetPreviousRankings

    robot.respond /history (\w+) ?(\d+|all)?$/i, historyMeRespond
    robot.respond /team history (\w+) (\w+) ?(\d+|all)?$/i, teamHistoryRespond
    robot.respond /rival history (\w+) (\w+) ?(\d+|all)?$/i, rivalHistoryRespond
    robot.respond /team stats (\w+) (\w+)$/i, teamStatsRespond

    robot.respond /go on (a )?cleanse$/i, goOnACleanseRespond
    robot.respond /return from cleanse$/i, returnFromCleanseRespond
    robot.respond /retire/i, retireRespond
    robot.respond /unretire/i, unretireRespond

    # Tournament commands
    robot.respond /start tournament$/i, startTournamentRespond
    robot.respond /start tournament with (\d+) people/i, startTournamentWithNPeopleRespond
    robot.respond /cancel tournament/i, cancelTournamentRespond
    robot.respond /show tournament$/i, showTournamentRespond
    robot.respond /show tournament players/i, showTournamentPlayersRespond
    robot.respond /show tournament teams/i, showTournamentTeamsRespond
    robot.respond /swap tournament player (\w+) with (\w+)/i, swapTournamentPlayersRespond
    robot.respond /accept tournament players/i, acceptTournamentPlayersRespond
    robot.respond /finish tournament game round (\d+) game (\d+) (\d-\d)/i, finishTournamentGameRespond

    # Betting commands
    robot.respond /start betting/i, startBettingRespond
    robot.respond /(my )?balance$/i, myBalanceRespond
    robot.respond /bet (\d+\.\d+) on game (\d+) team ([01])/i, betRespond
    robot.respond /all in on game (\d+) team ([01])/i, allInRespond
    robot.respond /cancel bet on game (\d+)/i, cancelBetRespond

    # Spending commands
    robot.respond /store/i, storeRespond
    robot.respond /buy (meme|time meme|dad joke|xkcd|adviceanimal|aww|funny|whoa)$/i, buyRespond(robot)
    robot.respond /buy (reddit) (\w+)$/i, buyRespond(robot)
    robot.respond /buy (meme|time meme|dad joke|xkcd|adviceanimal|aww|funny|whoa) for @?(\w+)/i, buyRespond(robot)

    # Helpful stuff
    robot.respond /the rules/i, theRulesRespond
    robot.respond /tip/i, tipRespond
    schedule.scheduleJob "0 30 11 * * 1-5", tipOfTheDaySend(robot)
    robot.respond /upload old rankings to influx/, uploadOldRankings
