module RomeoLib

using SubScreens
using TBCompletedM
using Romeo,  GLFW, GLAbstraction, Reactive, ModernGL, GLWindow, Color
using ImmutableArrays

export init_romeo, interact_loop,
       clear!,
       setDebugLevels
debugFlagOn  = false
debugLevel   = 0::Int64

#==       Level (ORed bit values)
           0x01: Show progress in fnWalk* functions (walk subscreen tree)
              2: Show debugging information related to pushing onto renderlist
              4: Debug connector
              8: 
           0x10: 
==#
 
#==  Set the debug parameters
==#
function setDebugLevels(flagOn::Bool,level::Int)
    global debugFlagOn
    global debugLevel
    debugFlagOn = flagOn
    debugLevel  = flagOn ? level : 0
end

dodebug(b::UInt8)  = debugFlagOn && ( debugLevel & Int64(b) != 0 )
dodebug(b::UInt32) = debugFlagOn && ( debugLevel & Int64(b) != 0 )
dodebug(b::UInt64) = debugFlagOn && ( debugLevel & Int64(b) != 0 )
@doc """   Empty the vector of renderers passed in argument, 
           and delete individually    each element.
     """   ->
function clear!(x::Vector{RenderObject})
    while !isempty(x)
        value = pop!(x)
        delete!(value)
    end
end
using DebugTools
using ROGeomOps       ## geometric OpenGL transformations on RenderObjects
using VirtualOGLGeom  ## tools to effect transformations on RenderObjects via
                      ## interfaces
using Connectors

@doc """  Performs a number of initializations
          Construct all RenderObjects (suitably parametrized) and inserts them in
          renderlist.

          It uses vizObjArray which is an array of functions building RenderObjects
          that corresponds (cell by cell based on indices) to the geometric grid built
          locally in subScreenGeom

          NOTE: THIS VERSION CORRESPONDS TO NON RECURSIVE=FLAT GRIDDING
                ** MIGHT BE PHASED OUT **
     """  -> 
function init_romeo(subScreenGeom, vizObjArray; pcamSel=true)
    root_area = Romeo.ROOT_SCREEN.area
    global_inputs = Romeo.ROOT_SCREEN.inputs

    # this enables sub-screen dimensions to adapt to  root window changes:
    # a signal is produced with root window's dimensions on display
    screen_height_width = lift(root_area) do area 
        Vector2{Int}(area.w, area.h)
    end

    areaGrid= mapslices(subScreenGeom ,[]) do ssc
          lift (Romeo.ROOT_SCREEN.area,  screen_height_width) do ar,screenDims
                RectangleProp(ssc,screenDims) 
          end
    end

    # Make subscreens of Screen type, each equipped with renderlist
    # We will then put RenderObject in each of the subscreens
    screenGrid= mapslices(areaGrid, []) do ar
        Screen(Romeo.ROOT_SCREEN, area=ar)
    end

   # Equip each subscreen with a RenderObject 


   for i = 1:size(screenGrid,1), j = 1:size(screenGrid,2)
       scr = screenGrid[i,j]

### old##       camera_input=copy(scr.inputs)
### old##       camera_input[:window_size] = lift(x->Vector4(x.x, x.y, x.w, x.h), scr.area)

       # the  selection of signals to drive cameras (in correct subscreen) is from S.Danisch example 
       # (synchronized subscreens)
       #checks if mouse is inside 
       insidescreen = lift(global_inputs[:mouseposition]) do mpos
             isinside(scr.area.value, mpos...) 
       end
       # creates signals for the camera, which are only active if mouse is inside screen
       camera_input = merge(global_inputs, Dict(
         :mouseposition  => keepwhen(insidescreen, Vector2(0.0), global_inputs[:mouseposition]), 
         :scroll_x       => keepwhen(insidescreen, 0, global_inputs[:scroll_x]), 
         :scroll_y       => keepwhen(insidescreen, 0, global_inputs[:scroll_y]), 
       ))
       #this is the reason we have to go through all this. For the correct perspective projection,
       # the camera needs the correct screen rectangle.
       camera_input[:window_size] = lift(x->Vector4(x.x, x.y, x.w, x.h), scr.area)

       eyepos = Vec3(2, 2, 2)
       centerScene= Vec3(0.0)

       pcam = PerspectiveCamera(camera_input,eyepos ,  centerScene)
       ocam=  OrthographicCamera(camera_input)
       camera = pcamSel ? pcam : ocam

       # Build the RenderObjects by calling the supplied function
       vo  = vizObjArray[i,j]( scr, camera )

       # The game here: thy shall not call visualize with a RenderObject
       # ( May be this can be simplified if  my proposed patch in Romeo/src/visualize_interface.jl
       # gets accepted)

       # passing screen= parameter to visualize inspired from test/simple_display_grid.jl
       viz = if ! isa(vo,Dict)
               visualize(vo, screen=scr)
           else
              # do not visualize RenderObjects!
              if ! (   isa(vo[:render],RenderObject) 
                    || isa(vo[:render],(RenderObject...)))
                 visualize(vo, screen=scr)
              else
                 vo
              end
       end

       #chkDump(viz,true) #debug (may be make this parameterized)

       if isa(viz,(RenderObject...))
            for v in viz
                push!(scr.renderlist, v)
            end
       else
            push!(scr.renderlist, viz)
       end

   end
end


@doc """  Performs a number of initializations
          Construct all RenderObjects (suitably parametrized) and inserts them in
          renderlist.
          
          The first argument is a fully a SubScreen (tree, with Rectangles 
          expanded/localized via computeRects  ). The attrib dictionnary is exploited 
          to set up the subscreens; all new objects are referenced via the SubScreen
          tree attrib dictionnaries.

          NOTE: THIS VERSION CORRESPONDS RECURSIVE GRIDDING: CURRENT LIBRARY CODE
     """  -> 
function init_romeo( vObjT::SubScreen; pcamSel=true)
    root_area = Romeo.ROOT_SCREEN.area
    global_inputs = Romeo.ROOT_SCREEN.inputs

    # this enables sub-screen dimensions to adapt to  root window changes:
    # a signal is produced with root window's dimensions on display
    screen_height_width = lift(root_area) do area 
        Vector2{Int}(area.w, area.h)
    end


    # set the subscreens areas as signals focused on subscreen rectangles
    fnWalk1 = function(ssc,indx,misc,info)
           info[:isDecomposed] && return
           ssc.attrib[sigArea ] = 
              lift (Romeo.ROOT_SCREEN.area,  screen_height_width) do ar,screenDims
                       RectangleProp(ssc,screenDims) 
                    end
          dodebug(0x01) && println("In fnWalk1 at$indx: sigArea=", ssc.attrib[sigArea ])
    end
    treeWalk!(vObjT,  fnWalk1)

    # Make subscreens of Screen type, each equipped with renderlist
    # We will then put RenderObject in each of the subscreens

    fnWalk2 = function(ssc,indx,misc,info)
         info[:isDecomposed] && return
         ssc.attrib[sigScreen ] =   Screen(Romeo.ROOT_SCREEN, area= ssc.attrib[sigArea ])
    end
    treeWalk!(vObjT,  fnWalk2)


   # Equip each subscreen with a RenderObject 

    fnWalk3 = function( ssc::SubScreen, 
                        indx::Vector{(Int64,Int64)}, 
			misc::Dict{Symbol,Any}, info::Dict{Symbol,Any})
       info[:isDecomposed] && return
       haskey(ssc.attrib,RObjFn )  || return

       scr = ssc.attrib[sigScreen ]
       # the  selection of signals to drive cameras (in correct subscreen) is from 
       # S.Danisch example  (synchronized subscreens)

       #checks if mouse is inside 
       insidescreen = lift(global_inputs[:mouseposition]) do mpos
             isinside(scr.area.value, mpos...) 
       end
       # creates signals for the camera, which are only active if mouse is inside screen
       camera_input = merge(global_inputs, Dict(
         :mouseposition  => keepwhen(insidescreen, Vector2(0.0), global_inputs[:mouseposition]), 
         :scroll_x       => keepwhen(insidescreen, 0, global_inputs[:scroll_x]), 
         :scroll_y       => keepwhen(insidescreen, 0, global_inputs[:scroll_y]), 
       ))
       #this is the reason we have to go through all this. For the correct 
       #perspective projection, the camera needs the correct screen rectangle.
       camera_input[:window_size] = lift(x->Vector4(x.x, x.y, x.w, x.h),scr.area)

       #default perspective parametrization (may be done better or parametrized)
       eyepos = Vector3{Float32}(2, 2, 2)
       centerScene= Vector3{Float32}(0.0)
       # when the user specifies a rotation we start from an eye aligned with
       # the x axis
       if haskey(ssc.attrib,RORot) 
           eyepos = Vector3{Float32}(3.5, 0, 0)
       end

       # Model space transformations which amount to changes in camera
       # position/center of view
       eyepos ,  centerScene = effVModelGeomCamera(ssc,eyepos, centerScene)

       pcam = PerspectiveCamera(camera_input,eyepos ,  centerScene)
       ocam=  OrthographicCamera(camera_input)
       camera = pcamSel ? pcam : ocam

       # Build the RenderObjects by calling the supplied function
       vo  = ssc.attrib[ RObjFn ]( scr, camera )


       # The game here: thy shall not call visualize with a RenderObject
       # ( May be this can be simplified if  my proposed patch in 
       # Romeo/src/visualize_interface.jl gets accepted)

       #screen= parameter to visualize inspired from test/simple_display_grid.jl
       viz =  if isa( vo, NotComplete)
                if haskey(vo.data, :SetPerspectiveCam)
                      scr.perspectivecam = camera
                      visualize(vo.what, screen=scr )
                elseif  haskey(vo.data, :doColorChooser)
                      visualize(vo.what)      
                else 
                  error("Unknown or absent key for TBCompleted ")
                end
           elseif ! isa(vo,Dict)
               visualize(vo, screen=scr)
           else
              # do not visualize RenderObjects!
              if ! (   isa(vo[:render],RenderObject) 
                    || isa(vo[:render],(RenderObject...)))
                 visualize(vo, screen=scr)
              else
                 vo
              end
       end
       ssc.attrib[ROProper] = viz


       # Does the user request virtual functions (we need to verify availability or diagnose)
       marker  = haskey(ssc.attrib,ROReqVirtUser) ? ssc.attrib[ROReqVirtUser] : 0
       # Check availability, this will use an external function (in ad hoc module!)
       #TBD!!!
       if  marker  != 0
            if isa(viz,RenderObject) && haskey(viz.manipVirtuals, ROReqVirtUser)
               println("Need to check avail of $marker in",
                        viz.manipVirtuals[ROReqVirtUser]  )
            else
               warn("Cannot check availability of feature $marker in $viz")
            end
       end

       # this way the user can request a dump 
       if haskey(ssc.attrib,RODumpMe)
          println("Dump for object viz of type = ",typeof(viz),"")
          function dumpIntern(viz)
              for k in sort(collect(keys( viz.uniforms)))
                 println("RODumpMe\tuniform\tkey=$k")
	      end
          end
          if isa(viz,(Any...))
             for v in viz
              isa(v,RenderObject) ?  dumpIntern(v) : @show v
             end
          elseif isa(viz,RenderObject)
              dumpIntern(viz)
          else
              @show viz
          end
       end

       if isa(viz,(RenderObject...))
            for v in viz
                push!(scr.renderlist, v)
            end
       elseif  isa(viz,(Any...))  
          # here deal with the case of color
          # where a pair (GLAbstraction.RenderObject,
          #               Reactive.Lift{ImmutableArrays.Vector4{Float32}})
            for v in viz
                if   isa(v,RenderObject)  push!(scr.renderlist, v)
                     # discard the Lift.... ? Good or Bad??

                     # Here  we set an attribute (we could use a signal)
                     dodebug(0x02) && chkDump(v,true)
                     v.uniforms[:swatchsize]=Input(4.0f0)
                end
            end
       else
            push!(scr.renderlist, viz)
       end

    end   # function  fnWalk3

    treeWalk!(vObjT,  fnWalk3)

# 4th pass for  operations which require multiple RO built (so that 
# we do not have to care about order of RO construction
    function fnWalk4( ssc::SubScreen, 
                        indx::Vector{(Int64,Int64)}, 
			misc::Dict{Symbol,Any}, info::Dict{Symbol,Any})
       info[:isDecomposed] && return
       haskey(ssc.attrib,ROConnects )  || return
       haskey(ssc.attrib,RObjFn )  || return

       #recover the connector list
       connectTo::Array{Connector,1}     = ssc.attrib[ROConnects]
       #these connectors are by necessity incomplete, must be completed
       for conn in  connectTo
            conn.to           = ssc.attrib[ROProper]
            #go from screen to RenderObject (is this really needed here ??)
            conn.from         = conn.from.attrib[ROProper]
       end
       dodebug( 0x04 ) && println("At index=$indx, connector list=$connectTo")       
       connect!(connectTo)

    end #  function fnWalk4

    treeWalk!(vObjT,  fnWalk4)


end

function interact_loop()
   while Romeo.ROOT_SCREEN.inputs[:open].value
      glEnable(GL_SCISSOR_TEST)
      Romeo.renderloop(Romeo.ROOT_SCREEN)
      sleep(0.01)
   end
   GLFW.Terminate()
end
end # 		module RomeoLib