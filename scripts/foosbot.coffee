# Description:
#   An LCB bot that arranges foosball games
#
# Commands:
#   foosbot Games
#   foosbot Games
#   foosbot Games
#   foosbot Games
#   foosbot Games
#   foosbot Games
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


gamesRespond = (res) ->
    # TODO: List the games, in groups of 4, with the indices
    res.send "games"


startGameRespond = (res) ->
    # TODO: Create a new group of four, at the end of the games array
    res.send "start game"


findPeopleForGameRespond = (res, n) ->
    n = if !n then parseInt(res.match[1].trim(), 10) else n

    # TODO: Ask @all who's up for a game, and announce who's currently part of the nth game
    res.send "find people for game #{n}"


joinGameRespond = (res, n, any) ->
    n = if !n then parseInt(res.match[1].trim(), 10) else n
    any = if !any then false else true

    # TODO: Add yourself to the nth game
    # TODO: Cannot join if full
    # TODO: If any is set, will try to add you to any game that's free, and will suggest starting one if none are
    res.send "join game #{n}"


abandonGameRespond = (res, n) ->
    n = if !n then parseInt(res.match[1].trim(), 10) else n
    
    # TODO: Abandon the nth game, freeing your spot in it
    res.send "abandon game #{n}"


cancelGameRespond = (res, n) ->
    n = if !n then parseInt(res.match[1].trim(), 10) else n

    # TODO: Cancel the nth game
    res.send "cancel game #{n}"


findPeopleForNextGameRespond = (res) ->
    # Ask @all who's up for a game, and announce who's currently part of the next upcoming game
    findPeopleForGameRespond(res, 0)


joinNextGameRespond = (res) ->
    # Add yourself to the next game
    # Cannot join if full
    joinGameRespond(res, 0)


joinAnyGameRespond = (res) ->
    # Add yourself to the next game that isn't full
    # If no games are free, suggest starting a new game
    joinGameRespond(res, 0, true)


abandonNextGameRespond = (res) ->
    # Abandon the next upcoming game, freeing your spot in it
    abandonGameRespond(res, 0)


cancelNextGameRespond = (res) ->
    # Cancel the next upcoming game
    cancelGameRespond(res, 0)


finishGameRespond = (res) ->
    team1_p1 = res.match[1].trim()
    team1_p2 = res.match[2].trim()
    
    team2_p1 = res.match[3].trim()
    team2_p2 = res.match[4].trim()

    team1_score = parseInt(res.match[5].trim(), 10)
    team2_score = parseInt(res.match[6].trim(), 10)

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


module.exports = (robot) ->
  robot.respond /games/i, (res) -> gamesRespond

  robot.respond /find people for game (\d+)/i, (res) -> findPeopleForGameRespond
  robot.respond /join game (\d+)/i, (res) -> joinGameRespond
  robot.respond /abandon game (\d+)/i, (res) -> abandonGameRespond
  robot.respond /cancel game (\d+)/i, (res) -> cancelGameRespond
  
  robot.respond /start game/i, (res) -> startGameRespond
  robot.respond /find people$/i, (res) -> findPeopleForNextGameRespond
  robot.respond /join/i, (res) -> joinNextGameRespond
  robot.respond /join next game/i, (res) -> joinNextGameRespond
  robot.respond /join any game/i, (res) -> joinAnyGameRespond
  robot.respond /abandon/i, (res) -> abandonNextGameRespond
  robot.respond /abandon next game/i, (res) -> abandonNextGameRespond
  robot.respond /cancel/i, (res) -> cancelNextGameRespond
  robot.respond /cancel next game/i, (res) -> cancelNextGameRespond

  robot.respond /finish game: +(\w+) +and +(\w+) +vs\.? +(\w+) +and +(\w+), +final +score +(\d+) *- *(\d+)$/i, (res) -> finishGameRespond
