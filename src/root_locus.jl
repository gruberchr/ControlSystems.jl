const Polynomials = ControlSystemsBase.Polynomials
import ControlSystemsBase.RootLocusResult
@userplot Rlocusplot


function getpoles(G, K::Number)
    issiso(G) || error("root locus only supports SISO systems")
    G isa TransferFunction || (G = tf(G))
    P = numpoly(G)[]
    Q = denpoly(G)[]
    T = float(typeof(K))
    ϵ = eps(T)
    nx = length(Q)
    D = zeros(nx-1, nx-1) # distance matrix
    prevpoles = ComplexF64[]
    temppoles = zeros(ComplexF64, nx-1)
    f = function (_,_,k)
        if k == 0 && length(P) > length(Q)
            # More zeros than poles, make sure the vector of roots is of correct length when k = 0
            # When this happens, there are fewer poles for k = 0, these poles can be seen as beeing located somewhere at Inf
            # We get around the problem by not allowing k = 0 for non-proper systems.
            k = ϵ
        end
        newpoles = ComplexF64.(Polynomials.roots(k[1]*P+Q))
        if !isempty(prevpoles)
            D .= abs.(newpoles .- transpose(prevpoles))
            assignment, cost = Hungarian.hungarian(D)
            for i = 1:nx-1
                temppoles[assignment[i]] = newpoles[i]
            end
            newpoles .= temppoles
        end
        prevpoles = newpoles
        newpoles
    end
    prob       = OrdinaryDiffEq.ODEProblem(f,f(0.,0.,0),(0,K[end]))
    integrator = OrdinaryDiffEq.init(prob,OrdinaryDiffEq.Tsit5(),reltol=1e-8,abstol=1e-8)
    ts         = Vector{Float64}()
    poleout    = Vector{Vector{ComplexF64}}()
    push!(poleout,integrator.k[1])
    push!(ts,0)
    for i in integrator
        push!(poleout,integrator.k[end])
        push!(ts,integrator.t[1])
    end
    poleout = copy(hcat(poleout...)')
    poleout, ts
end


function getpoles(G, K::AbstractVector{T}) where {T<:Number}
    issiso(G) || error("root locus only supports SISO systems")
    G isa TransferFunction || (G = tf(G))
    P, Q = numpoly(G)[], denpoly(G)[]
    poleout = Matrix{ComplexF64}(undef, Polynomials.degree(Q), length(K))
    nx = length(Q)
    D = zeros(nx-1, nx-1) # distance matrix
    temppoles = zeros(ComplexF64, nx-1)
    for (i, k) in enumerate(K)
        k == 0 && length(P) > length(Q) && (k = eps(T))
        poleout[:,i] = ComplexF64.(Polynomials.roots(k[1]*P+Q))
        if i > 1
            D .= abs.(poleout[:,i] .- transpose(poleout[:,i-1]))
            assignment, _ = Hungarian.hungarian(D)
            foreach(k->temppoles[assignment[k]] = poleout[:,i][k], 1:nx-1)
            poleout[:,i] .= temppoles
        end
    end
    copy(poleout'), K
end


"""
    roots, Z, K = rlocus(P::LTISystem, K = 500)

Compute the root locus of the SISO LTISystem `P` with a negative feedback loop and feedback gains between 0 and `K`. `rlocus` will use an adaptive step-size algorithm to determine the values of the feedback gains used to generate the plot.

`roots` is a complex matrix containig the poles trajectories of the closed-loop `1+k⋅G(s)` as a function of `k`, `Z` contains the zeros of the open-loop system `G(s)` and `K` the values of the feedback gain.
"""
function rlocus(P, K)
    Z = tzeros(P)
    roots, K = getpoles(P,K)
    ControlSystemsBase.RootLocusResult(roots, Z, K, P)
end

rlocus(P; K=500) = rlocus(P, K)


# This will be called on plot(rlocus(sys, args...))
@recipe function rootlocusresultplot(r::RootLocusResult)
    roots, Z, K = r
    redata = real.(roots)
    imdata = imag.(roots)
    all_redata = [vec(redata); real.(Z)]
    all_imdata = [vec(imdata); imag.(Z)]

    ylims --> (max(-50,minimum(all_imdata) - 1), min(50,maximum(all_imdata) + 1))
    xlims --> (max(-50,minimum(all_redata) - 1), clamp(maximum(all_redata) + 1, 1, 50))
    framestyle --> :zerolines
    title --> "Root locus"
    xguide --> "Re(roots)"
    yguide --> "Im(roots)"
    form(k, p) = Printf.@sprintf("%.4f", k) * "  pole=" * Printf.@sprintf("%.3f%+.3fim", real(p), imag(p))
    @series begin
        legend --> false
        hover := "K=" .* form.(K,roots)
        label := ""
        redata, imdata
    end
    @series begin
        seriestype := :scatter
        markershape --> :circle
        markersize --> 10
        label --> "Zeros"
        real.(Z), imag.(Z)
    end
    @series begin
        seriestype := :scatter
        markershape --> :xcross
        markersize --> 10
        label --> "Open-loop poles"
        redata[1,:], imdata[1,:]
    end
end


"""
    rlocusplot(P::LTISystem; K)

Plot the root locus of the SISO LTISystem `P` as computed by `rlocus`.
"""
@recipe rlocusplot(::Type{Rlocusplot}, p::Rlocusplot; K=500) =
    rlocus(p.args[1]; K=K)
