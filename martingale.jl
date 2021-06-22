# Import libraries

using Random
using Statistics
using DataFrames    # If necessary, download the package at the pkg prompt, i.e. add DataFrames
using Distributions # You may need to run in your command prompt: julia -e 'import Pkg; Pkg.add("Distributions")'
using StatsBase     # You may need to run in your command prompt: julia -e 'import Pkg; Pkg.add("StatsBase")'
using Printf        # You may need to run in your command prompt: julia -e 'import Pkg; Pkg.add("Printf")'
using CSV           # You may need to run in your command prompt: julia -e 'import Pkg; Pkg.add("CSV")'
using Dates
using Base.Iterators
using ArgParse       # You may need to run in your command prompt: julia -e 'import Pkg; Pkg.add("ArgParse")'
using DelimitedFiles # In order to output delimited files (like arrays)
using Plots          # You may need to run in your command prompt: julia -e 'import Pkg; Pkg.add("Plots")'
using Plots.PlotMeasures

# Function to seed the randomizer
function get_seed()
    return 42
end

function get_spin_results(
    trial_count  :: Int64;
    win_prob     :: Float64 = 18.0/38.0 # American Roulette probability of red/black, even/odd, low/high
)
    @assert (win_prob >= 0) & (win_prob <= 1.0) "Parameter 'win_prob' must be between 0.0 and 1.0"

    @assert (trial_count >= 1) & (trial_count < 100000) "Parameter 'trial_count' must be between 1 and 99999"
        
    # Generate an array of True/False values and convert the results
    # to ints so that we can do some arithmetic on them
    return convert(Vector{Int64}, rand(Distributions.Bernoulli(win_prob), trial_count))
end

function configure_text_overlay(
    ; text_loc_x              =   0.5
    , text_loc_y              =   0.5
    , text                    =   "CESAR\nMUGNATTO"
    , alignment               =   :center
    , fontfamily              =   "Verdana"
    , fontscale               =   0.1
    #, color                   =   RGBA(0, 1, 0, 64.0/255.0) # Corresponds to #00FF0040
    , color                   =   RGBA(128.0/255.0, 0, 1, 96.0/255.0) # Corresponds to #8000FF60
    , rotation                =   45
)
    text_overlay = Dict(
          "text_loc_x"          => text_loc_x
        , "text_loc_y"          => text_loc_y
        , "text"                => text
        , "alignment"           => alignment
        , "fontfamily"          => fontfamily
        , "fontscale"           => fontscale
        , "color"               => color
        , "rotation"            => rotation
    )

    return text_overlay

end

# Ensure our output directory exists
#mkpath("output")

# Create a text file for recording diagnostic data
#file_diagnostics = open("output/diagnostics.txt", "w")
#time_start = now()
#@printf(file_diagnostics, "Started at: %s\n", time_start)

function run_episode(
      win_prob              :: Float64
    , episode_size          :: Int64
    , max_winnings_desired  :: Int64
    # Optional parameters follow
    ; fh_WinsLosses         :: Union{ IOStream, Nothing } = nothing
)
    @assert (win_prob >= 0.0) && (win_prob <= 1.0) "Parameter 'win_prob' must be between 0.0 and 1.0"

    @assert (episode_size > 0) && (episode_size < 100000) "Parameter 'episode_size' must be between 1 and 99999"

    @assert max_winnings_desired > 0 "Parameter 'max_winnings_desired' must be greater than 0"

    @assert (typeof(fh_WinsLosses) == Nothing) || (typeof(fh_WinsLosses) == IOStream && isopen(fh_WinsLosses)) "Parameter 'fh_WinsLosses' must be an open IOStream or Nothing"

    # Get our array of True/False trials returned as ints ( 1/0 )
    trial_wins = get_spin_results(episode_size; win_prob=win_prob)
    # For testing:
    #trial_wins = convert(Vector{Int64}, [0, 1, 0, 1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1])
    if typeof(fh_WinsLosses) == IOStream
        writedlm(fh_WinsLosses, trial_wins', ',') # Use the single-quote transpose (i.e. trial_wins' rather than trial_wins)
    end

    # Take the complement of wins as losses (win = 0 implies loss = -1)
    trial_losses = Int64.(trial_wins .- 1)

    # Use Iterator to accumulate the value of losses, using a lambda function
    # for the accumulator (to reset the betting to $1 after each winning bet)
    trial_losses_copy = Int64.(collect(Iterators.accumulate((start, next)->(next==0 ? 1 : 2*start), abs.(trial_losses); init=1)))

    # Shift the resulting array to the right by 1 (dropping the last elements)
    # and insert the first bet (always $1) as the first bet in the array
    bet_amounts = append!([Int64(1)], trial_losses_copy[1:length(trial_losses_copy)-1])

    # Multiply our calculated bet amounts by positive or negative 1 depending on whether we won or lost the bet
    winnings_per_round = bet_amounts .* (trial_wins + trial_losses)

    # Now use cumsum to accumulate the winnings per round
    accumulated_winnings = Int64.(cumsum(winnings_per_round))

    # Finally, use Iterator to take all entries in accumulated winnings that are less than our "target" amount
    accumulated_winnings_no_max = Int64.(collect(Iterators.takewhile(x -> x < max_winnings_desired, accumulated_winnings)))
    # If we reached our target amount, pad the remaining values with our final winnings
    if length(accumulated_winnings_no_max) < episode_size
        max_winnings = accumulated_winnings[length(accumulated_winnings_no_max) + 1]
        accumulated_winnings = append!(accumulated_winnings_no_max, Int64.(ones(episode_size - length(accumulated_winnings_no_max) - 1) * max_winnings))
    end
    
    # Because it's required, we need to prefix the value 0 for winnings to the numpy array
    # We also truncate the array at the end by one position to mke room for that first 0
    accumulated_winnings = append!([Int64(0)], accumulated_winnings)[1:episode_size]

    return Int64.(accumulated_winnings)
end

function run_episode_limit(
      win_prob              :: Float64
    , episode_size          :: Int64
    , max_winnings_desired  :: Int64
    , loss_limit            :: Int64
    # Optional parameters follow
    ; fh_WinsLosses         :: Union{ IOStream, Nothing } = nothing
)
    @assert (win_prob >= 0.0) && (win_prob <= 1.0) "Parameter 'win_prob' must be between 0.0 and 1.0"

    @assert (episode_size > 0) && (episode_size < 100000) "Parameter 'episode_size' must be between 1 and 99999"

    @assert max_winnings_desired > 0 "Parameter 'max_winnings_desired' must be greater than 0"

    @assert loss_limit > 0 "Parameter 'loss_limit' must be greater than 0"

    @assert (typeof(fh_WinsLosses) == Nothing) || (typeof(fh_WinsLosses) == IOStream && isopen(fh_WinsLosses)) "Parameter 'fh_WinsLosses' must be an open IOStream or Nothing"

    # Get our array of True/False trials returned as ints ( 1/0 )
    trial_wins = get_spin_results(episode_size; win_prob=win_prob)
    # For testing:
    #trial_wins = convert(Vector{Int64}, [0, 1, 0, 1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1])
    if typeof(fh_WinsLosses) == IOStream
        writedlm(fh_WinsLosses, trial_wins', ',') # Use the single-quote transpose (i.e. trial_wins' rather than trial_wins)
    end

    # Shortcut: If we ever run out of money before getting to our desired winnings i.e.
    # bankroll of 256 (loss_limit) + desire winnings of 80 (max_winnings_desired) = 336,
    # then we have a potentially losing episode. We would lose all our money
    # if the number of consecutive bits (powers of 2) that are 0 (i.e. losses)
    # exceeds the bankroll + desired winnings - 1. We can use the function ndigits(, base=2)
    # to see how many such consecutive zeros we would need to see before we can declare
    # this episode as a potential loser. The only way it would still be a winning episode
    # would be if we reached the desired winnings before we lose everything. But in any case,
    # we do not need to process the entire array - only up to the index of the end of the
    # 9 zeros in our array of wins and losses. Technically, we should still calculate
    # how many consecutive zeros would constitute a loss (in case our parameters change) so:
    zero_count = loss_limit == 0 ? 1 : ndigits(loss_limit + max_winnings_desired - 1, base=2)

    # The zero_count is expected to be a number > 1, even though we return a 1 in the default case.
    # This is because this function is only called when we have a limit on losses
    # (we arrive at the casino with a set bankroll). In order to get the accumulated losses correct
    # we need to look for this number of sequential 0 values in our trial_wins array
    zero_sequence = repeat("0", zero_count)
    idx_zero_sequence = findnext(zero_sequence, join(string.(trial_wins)), 1)
    if typeof(idx_zero_sequence) != Nothing
        idx_zero_sequence = idx_zero_sequence[1] + zero_count - 1
    else
        idx_zero_sequence = length(trial_wins)
    end

    # Reset length of trial_wins to the shortest of:
    # 1. Location at the end of the first sequence of zeros
    # 2. The original end of the trial_wins array
    trial_wins = trial_wins[1:idx_zero_sequence]

    # Take the complement of wins as losses (win = 0 implies loss = -1)
    trial_losses = Int64.(trial_wins .- 1)

    # Use Iterator to accumulate the value of losses, using a lambda function
    # for the accumulator (to reset the betting to $1 after each winning bet)
    trial_losses_copy = Int64.(collect(Iterators.accumulate((start, next)->(next==0 ? 1 : 2*start), abs.(trial_losses); init=1)))

    # Shift the resulting array to the right by 1 (dropping the last elements)
    # and insert the first bet (always $1) as the first bet in the array
    bet_amounts = append!([Int64(1)], trial_losses_copy[1:length(trial_losses_copy)-1])

    # Multiply our calculated bet amounts by positive or negative 1 depending on whether we won or lost the bet
    winnings_per_round = bet_amounts .* (trial_wins + trial_losses)

    # Now use cumsum to accumulate the winnings per round
    accumulated_winnings = Int64.(cumsum(winnings_per_round))

    # The amount of money we have available to bet is any winnings + the amount we brought to the casino
    # Prepend the original bankroll as the first value in the array and push all the others out to the right by 1 position
    available_to_bet = append!([loss_limit], (accumulated_winnings .+ loss_limit))[1:idx_zero_sequence]

    # See if we tried to bet more than we could at any point of our episode, and adjust if necessary
    # Do this by taking the minimum of available money - bets, and 0
    exceeded_bets = Int64.(min.(available_to_bet .- bet_amounts, 0))

    # Then add (or because the minimum may be ngative, subtract) those amounts
    # from the originally intended bet amounts to get bet amounts limited by how much money we hold
    limited_bet_amounts = bet_amounts .+ exceeded_bets

    # Adjust the winnings per round by limiting where the bet amount exceeded our available funds
    # When we add trial_wins (a sequence of 1s and 0s) to trial_losses (a complementary sequence of 0s and -1s)
    # we get a sequence of 1s and -1s which when multiplied by the amout bet will give us wins and losses in dollar amounts
    limited_winnings_per_round = Int64.(abs.(limited_bet_amounts) .* (trial_wins .+ trial_losses))

    # Recalculate the accumulated winnings based on limited bet amounts (if any)
    limited_accumulated_winnings = Int64.(cumsum(limited_winnings_per_round))

    # There are two early stop conditions
    # 1. The winnings meet or exceed the "target" amount we are content with winning for that episode
    # 2. We run out of money during the execution of that episode

    # Finally, use Iterator to take all entries in accumulated winnings that are less than our "target" amount
    accumulated_winnings_target = Int64.(collect(Iterators.takewhile(x -> x < max_winnings_desired, limited_accumulated_winnings)))

    # Use itertools to take all entries in accumulated winnings that are greater than 0 after adding the money we brought to the casino
    accumulated_winnings_solvent = Int64.(collect(Iterators.takewhile(x -> x >= -loss_limit, limited_accumulated_winnings)))

    # Final amount
    if length(accumulated_winnings_solvent) == length(accumulated_winnings_target)
        # We neither went bust, nor hit our desired target for winnings
        # Just set the final winnings to either of the two arrays being compared
        final_winnings = accumulated_winnings_target[end]
        limited_accumulated_winnings = append!(accumulated_winnings_solvent, Int64.(ones(episode_size - length(accumulated_winnings_solvent)) * final_winnings))
    elseif length(accumulated_winnings_solvent) < length(accumulated_winnings_target)
        # We went broke before reaching the "target" amount
        # Set the final winnings to the loss of our bankroll and broadcast to remainder of the episode
        final_winnings = -loss_limit
        limited_accumulated_winnings = append!(accumulated_winnings_solvent, Int64.(ones(episode_size - length(accumulated_winnings_solvent)) * final_winnings))
    elseif length(accumulated_winnings_target) <= idx_zero_sequence
        # We reached our "target" amount before the end of the episode
        # Broadcast that final amount to remainder of the episode
        if length(accumulated_winnings_target) == episode_size
            final_winnings = limited_accumulated_winnings[end]
        else
            final_winnings = limited_accumulated_winnings[length(accumulated_winnings_target)+1]
        end
        limited_accumulated_winnings = append!(accumulated_winnings_target, Int64.(ones(episode_size - length(accumulated_winnings_target)) * final_winnings))
    end
    
    # Because it's required, we need to prefix the value 0 for winnings to the numpy array
    # We also truncate the array at the end by one position to mke room for that first 0
    limited_accumulated_winnings = append!([Int64(0)], limited_accumulated_winnings)[1:episode_size]

    return Int64.(limited_accumulated_winnings)

end

function run_report_episodes(
      win_prob             :: Float64
    , num_episodes         :: Int64
    , episode_size         :: Int64
    , max_winnings_desired :: Int64
    , fh_WinsLosses        :: Union{ IOStream, Nothing }
    , out_file_name        :: String
    , plot_title           :: String
    , do_plot_mean         :: Bool
    , do_plot_median       :: Bool
    , text_overlay         :: Union{ Dict, Nothing }
    , savecsv              :: Bool
    # Optional parameters follow
    #; data                 :: Union{ Vector{Vector{Int64}}, Nothing } = nothing
    ; data                 :: Union{ Array{Int64}, Nothing } = nothing
    , loss_limit           :: Int64 = Int64(0)
)
    @assert (win_prob >= 0.0) && (win_prob <= 1.0) "Parameter 'win_prob' must be between 0.0 and 1.0"

    @assert (episode_size > 0) && (episode_size < 100000) "Parameter 'episode_size' must be between 1 and 99999"

    @assert max_winnings_desired > 0 "Parameter 'max_winnings_desired' must be greater than 0"

    @assert loss_limit >= 0 "Parameter 'loss_limit' must be greater than 0"

    @assert (typeof(fh_WinsLosses) == Nothing) || (typeof(fh_WinsLosses) == IOStream && isopen(fh_WinsLosses)) "Parameter 'fh_WinsLosses' must be an open IOStream or Nothing"

    # Create a list to hold our results
    #vec_episode_winnings = Vector{Vector{Int64}}()
    # Or should we use:
    vec_episode_winnings = Array{Int64}(undef, num_episodes, episode_size)

    # There may be a much more efficient way in Julia to add data to a 2-D structure
    # than what I'm doing below, but I'm still trying to wrap my head around the
    # column-wise ordering of Julia Arrays, and how to work with them efficiently:
    # https://stackoverflow.com/questions/36727839/add-a-row-to-a-matrix-in-julia
    # https://discourse.julialang.org/t/silly-question-how-to-add-a-row-to-array/33601
    # Questions arise over whether it is better to create a zero matrix up front
    # with a known size and then overwrite the rows with new data, or other alternatives
    if typeof(data) == Nothing
        if loss_limit == 0
            for i in 1:num_episodes
                #vec_episode_winnings = vcat(vec_episode_winnings, [run_episode(win_prob, episode_size, max_winnings_desired; fh_WinsLosses)])
                vec_episode_winnings[i, :] = run_episode(win_prob, episode_size, max_winnings_desired; fh_WinsLosses)
            end
        else
            for i in 1:num_episodes
                #vec_episode_winnings = vcat(vec_episode_winnings, [run_episode_limit(win_prob, episode_size, max_winnings_desired, loss_limit; fh_WinsLosses)])
                vec_episode_winnings[i, :] = run_episode_limit(win_prob, episode_size, max_winnings_desired, loss_limit; fh_WinsLosses)
            end
        end
    else
        vec_episode_winnings = data
    end

    if savecsv
        writedlm("$(out_file_name).csv", vec_episode_winnings, ',')
    end

    x_lim_min = 0
    x_lim_max = 300
    y_lim_min = -256
    y_lim_max = 100
    x_plot_size = 600
    y_plot_size = 600
    x_label = "# of spins"
    y_label = "Winnings"

    if !(do_plot_mean || do_plot_median)
        labels = Array{String}(undef, 1, num_episodes)
        labels[1, :] = ["Episode $(i)" for i in 1:num_episodes]
        plot_series = vec_episode_winnings'
    else
        std_episode_winnings = Statistics.std(vec_episode_winnings, dims=1)
    end

    if (do_plot_mean)
        mean_episode_winnings = Statistics.mean(vec_episode_winnings, dims=1)
        mean_plus_std = mean_episode_winnings .+ std_episode_winnings
        mean_minus_std = mean_episode_winnings .- std_episode_winnings
        plot_series = [mean_episode_winnings' mean_plus_std' mean_minus_std']
        labels = ["Mean" "Mean + Std Dev" "Mean - Std Dev"]
    end

    if (do_plot_median)
        med_episode_winnings = Statistics.median(vec_episode_winnings, dims=1)
        med_plus_std = med_episode_winnings .+ std_episode_winnings
        med_minus_std = med_episode_winnings .- std_episode_winnings
        plot_series = [med_episode_winnings' med_plus_std' med_minus_std']
        labels = ["Median" "Median + Std Dev" "Median - Std Dev"]
    end

    my_plot = plot(
          plot_series
        , xlims         = (x_lim_min, x_lim_max)
        , ylims         = (y_lim_min, y_lim_max)
        , size          = (x_plot_size, y_plot_size)
        , label         = labels
        , title         = plot_title
        , xlabel        = x_label
        , ylabel        = y_label
        , legend        = :bottomright
        , bottom_margin = 10mm
        , left_margin   = 15mm
        , right_margin  = 5mm
        , top_margin    = 0mm
    )

    # Any of the following can test whether text_overlay is a Dict variable
    #if typeof(text_overlay) == Dict{String, Any}
    #if typeof(text_overlay) <: Dict
    if isa(text_overlay, Dict)
        text_loc_x = Int16(round((x_lim_max - x_lim_min) * text_overlay["text_loc_x"])) + x_lim_min
        text_loc_y = Int16(round((y_lim_max - y_lim_min) * (1- text_overlay["text_loc_y"]))) + y_lim_min
        fontsize = Int16(round(min(x_plot_size, y_plot_size) * text_overlay["fontscale"]))
        #println("($(text_loc_x), $(text_loc_y))")
        annotate!([
            (
                  text_loc_x
                , text_loc_y
                , Plots.text(
                    text_overlay["text"]
                    , text_overlay["color"]
                    , text_overlay["alignment"]
                    , fontsize
                    , text_overlay["fontfamily"]
                    , rotation=text_overlay["rotation"]
                )
            )
        ])
    end

    savefig("$(out_file_name).png")

    return vec_episode_winnings
    
end

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--watermark"
            arg_type = Bool
            default = false
        "--savecsv"
            arg_type = Bool
            default = false
    end

    return parse_args(s)
end

function main()

    # Ensure our output directory exists
    mkpath("output")

    Random.seed!(get_seed())

    win_prob = Float64(18.0/38.0)

    parsed_args = parse_commandline()

    watermark = parsed_args["watermark"]
    savecsv = parsed_args["savecsv"]

    if watermark
        text_overlay = configure_text_overlay()
    else
        text_overlay = nothing
    end

    episode_size = Int64(1000)
    num_episodes = Int64(10)
    max_winnings_desired = Int64(80)

    # Experiment 1 - Figure 1
    #------------------------
    plot_file = "output/01_01_Winnings"
    plot_title = "Roulette Winnings\nExperiment 1 - $(num_episodes) Episodes"
    outfile = "output/01_01_WinsLosses.csv"
    if savecsv
        fh_WinsLosses = open(outfile, "w")
        close(fh_WinsLosses)
        fh_WinsLosses = open(outfile, "a")
    else
        fh_WinsLosses = nothing
    end

    episode_winnings = run_report_episodes(
          win_prob
        , num_episodes
        , episode_size
        , max_winnings_desired
        , fh_WinsLosses
        , plot_file
        , plot_title
        , false
        , false
        , text_overlay
        , savecsv
        # Optional parameter values follow
        #; data = nothing
        #, loss_limit = Int64(256)
    )

    # Experiment 1 - Figure 2
    #------------------------
    episode_size = Int64(1000)
    num_episodes = Int64(1000)
    max_winnings_desired = Int64(80)

    plot_file = "output/01_02_Winnings"
    plot_title = "Roulette Winnings\nExperiment 1 - $(num_episodes) Episodes (with Mean)"
    outfile = "output/01_02_WinsLosses.csv"
    if savecsv
        fh_WinsLosses = open(outfile, "w")
        close(fh_WinsLosses)
        fh_WinsLosses = open(outfile, "a")
    else
        fh_WinsLosses = nothing
    end

    episode_winnings = run_report_episodes(
          win_prob
        , num_episodes
        , episode_size
        , max_winnings_desired
        , fh_WinsLosses
        , plot_file
        , plot_title
        , true
        , false
        , text_overlay
        , savecsv
        # Optional parameter values follow
        #; data = nothing
        #, loss_limit = Int64(256)
    )

    # Let's see how many of our 1,000 episodes achieved the desired winnings by the 1,000th spin of the wheel
    #success_count = count(z -> z != 0, ([fin[end] for fin in episode_winnings] .>= max_winnings_desired))
    success_count = count(z -> z != 0, episode_winnings[:, end] .>= max_winnings_desired)
    println("For Experiment 1 - Figure 2, of the $(num_episodes) episodes, $(success_count) achieved the goal of winning $(max_winnings_desired)")

    # Experiment 1 - Figure 3
    #------------------------
    episode_size = Int64(1000)
    num_episodes = Int64(1000)
    max_winnings_desired = Int64(80)

    plot_file = "output/01_03_Winnings"
    plot_title = "Roulette Winnings\nExperiment 1 - $(num_episodes) Episodes (with Median)"
    # No need to print this out - it is identical to the file "01_02_WinsLosses.csv"
    fh_WinsLosses = nothing

    episode_winnings = run_report_episodes(
          win_prob
        , num_episodes
        , episode_size
        , max_winnings_desired
        , fh_WinsLosses
        , plot_file
        , plot_title
        , false
        , true
        , text_overlay
        , false
        # Optional parameter values follow
        ; data = episode_winnings
        #, loss_limit = Int64(256)
    )

    # Experiment 2 - Figure 4
    #------------------------
    episode_size = Int64(1000)
    num_episodes = Int64(1000)
    max_winnings_desired = Int64(80)
    loss_limit = Int64(256)

    plot_file = "output/02_04_Winnings_limited"
    plot_title = "Roulette Winnings\nExperiment 2 - $(num_episodes) Episodes (with Mean, limit losses)"
    outfile = "output/02_04_WinsLosses_limited.csv"
    if savecsv
        fh_WinsLosses = open(outfile, "w")
        close(fh_WinsLosses)
        fh_WinsLosses = open(outfile, "a")
    else
        fh_WinsLosses = nothing
    end

    episode_winnings = run_report_episodes(
          win_prob
        , num_episodes
        , episode_size
        , max_winnings_desired
        , fh_WinsLosses
        , plot_file
        , plot_title
        , true
        , false
        , text_overlay
        , savecsv
        # Optional parameter values follow
        ; loss_limit = loss_limit
        #, data = nothing
    )

    # Let's see how many of our 1,000 episodes achieved the desired winnings by the 1,000th spin of the wheel
    #success_count = count(z -> z != 0, ([fin[end] for fin in episode_winnings] .>= max_winnings_desired))
    success_count = count(z -> z != 0, episode_winnings[:, end] .>= max_winnings_desired)
    println("For Experiment 2 - Figure 4, of the $(num_episodes) episodes, $(success_count) achieved the goal of winning $(max_winnings_desired)")

    # Experiment 2 - Figure 5
    #------------------------
    episode_size = Int64(1000)
    num_episodes = Int64(1000)
    max_winnings_desired = Int64(80)
    loss_limit = Int64(256)

    plot_file = "output/02_05_Winnings_limited"
    plot_title = "Roulette Winnings\nExperiment 2 - $(num_episodes) Episodes (with Median, limit losses)"
    # No need to print this out - it is identical to the file "02_04_WinsLosses_limited.csv"
    fh_WinsLosses = nothing

    episode_winnings = run_report_episodes(
          win_prob
        , num_episodes
        , episode_size
        , max_winnings_desired
        , fh_WinsLosses
        , plot_file
        , plot_title
        , false
        , true
        , text_overlay
        , false
        # Optional parameter values follow
        ; loss_limit = loss_limit
        , data = episode_winnings
    )

end

main()