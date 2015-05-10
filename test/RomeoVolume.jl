using Lumberjack

using Romeo

# try to avoid the numerous "deprecated warnings/messages"
using ManipStreams
(os,ns) =  redirectNewFWrite("/tmp/julia.redirected")

using GLVisualize, GLFW, GLAbstraction, Reactive, ModernGL, GLWindow, ColorTypes

using GeometryTypes
using TBCompletedM
using SubScreens
using Connectors

    #  Loading GLFW opens the window
using Compat
using LightXML

using  XtraRenderObjOGL
using RomeoLib

using ParseXMLSubscreen
using SemXMLSubscreen
using ColorTypes
@doc """ This function uses the XML interface to define a screen organized
         into subscreens.
     """  ->
function init_graph_gridXML(onlyImg::Bool, plotDim=2, xml="")
   # Here we need to read the XML and do whatever is needed
   # We have moved this before the definition of the functions below
   # because of the definition of plt below, which requires doPlot2D and
   # doPlot3D. This is also a good test of our parse strategy for XML chunks

   xdoc = parse_file(xml)
   parseTree = acDoc(xdoc)
   SemXMLSubscreen.setDebugLevels(true,0x20)   #debug
   sc = subscreenContext()

   # process the inline xml processing instructions
   xmlJuliaImport(parseTree,sc)
   

   # Now, we want to integrate functions defined programmatically here
   # and others which come from the XML subscreen description

   # here we have a rather stringent test: doPlot2D and doPlot3D are 
   # defined in the code inlined in XML (in module SubScreensInline)

   # Since it is created by parse, the module SubScreensInline is known
   # inside the context of the module specified when calling parse in 
   # SemXMLSubscreen.processInline. The function 
   # SemXMLSubscreen.__init__() provides the special module Main.xmlNS
   # for this context.
   SubScreensInline =  xmlNS.SubScreensInline

   println("names module xmlNS", names(xmlNS))
   println("names module SubScreensInline", names(SubScreensInline))
   plt = plotDim==2 ? SubScreensInline.doPlot2D : SubScreensInline.doPlot3D

   # put the cat all over the place!!!
   pic = (sc::Screen,cam::GLAbstraction.Camera)  -> Texture("pic.jpg")

   # volume : try with a cube (need to figure out how to make this)
   cube = (sc::Screen,cam::GLAbstraction.Camera)-> mkCube(sc,cam)

   # color
   # Unable to convert this function to GLVisualize
   function doColorChooser(sc::Screen,cam::GLAbstraction.Camera)
          TBCompleted (ColorTypes.AlphaColorValue( 
                       ColorTypes.RGB24(0xE0,0x10,0x10), float32(0.5)),
                       nothing, Dict{Symbol,Any}(:doColorChooser=> true))
   end
   colorBtn = doColorChooser

   # edit
   # this is an oversimplification!! (look at exemple!!)
   function doEdit(sc::Screen,cam::GLAbstraction.Camera)
     "barplot = Float32[(sin(i/10f0) + cos(j/2f0))/4f0 \n for i=1:10, j=1:10]\n"
   end
   # This is a table of provided functions, other have been already found when
   # parsing the xml
   fnDict = Dict{AbstractString,Function}("doEdit"=>pic, 
                                          "doColorBtn"=>plt, 
                                          "doCube" => plt, 
                 			  "doPic"=>pic, 
                                          "doPlot" => plt )
   # We insert these definitions in the namespace use by xml
   insertXMLNamespace(fnDict)
   println("After insertXMLNamespace names in Main.xmlNS:",names(Main.xmlNS))
   vizObj = buildFromParse( parseTree, sc)
   @show vizObj
   return vizObj

end  
@doc """
       Does the real work, main only deals with the command line options.
       - init_glutils    :initialization functions (see the GL* libraries)
       - init_graph_grid :prepare a description of the subscreens
       - init_romeo      :construct the subscreens, use the description
                          of subscreens to actually build them (calls visualize)
     """ ->
function realMain(onlyImg::Bool; pcamSel=true, plotDim=2,  xml::String="")
   init_glutils()
   vizObjSC   =        init_graph_gridXML(onlyImg, plotDim, xml)
   println("Entering  init_romeo")
   init_romeo( vizObjSC; pcamSel = pcamSel )

   println("Entering  interact_loop")
   interact_loop()
end

# parse arguments, so that we have some flexibility to vary tests on the 
# command line.
using ArgParse
function main(args)
     s = ArgParseSettings(description = "Test of Romeo with grid of objects")   
     @add_arg_table s begin
       "--dim"
               help="Set to 2 or 3 for 2D or 3D plot"
               arg_type = Int
       "--img","-i"   
               help="Use image instead of other graphics/scenes"
               action = :store_true
       "--debugAbs","-d"
               help="show debugging output (in particular from GLRender)"
               arg_type = Int
       "--xml","-x"
               help="enter the filename of the XML subscreen description"
               arg_type = String
       "--debugWin","-D"
               help="show debugging output (in particular from GLRender)"
               arg_type = Int
      "--ortho", "-o"       
               help ="Use orthographic camera instead of perspective"
               action = :store_true
       "--log","-l"
               help ="Use lumberjack log"
               arg_type = String

     end    

     s.epilog = """
       GLAbstraction debug levels (ORed bit values)
        Ox01     1 : add traceback for constructors and related
        0x04     4 : print uniforms
        0x08     8 : print vertices
        0x10    16 : reserved for GLTypes.GLVertexArray
        0x20    32 : reserved for postRenderFunctions

       GLWindow debug :
               flagOn : on / off
               *** Level (ORed bit values) :to be allocated ***
     """
    parsed_args = parse_args(s) # the result is a Dict{String,Any}

    onlyImg        = parsed_args["img"]
    pcamSel        = !parsed_args["ortho"]
    plotDim        = (parsed_args["dim"] != nothing) ?  parsed_args["dim"] : 2

    xml =  parsed_args["xml"] != nothing ? parsed_args["xml"] : ""

    if parsed_args["log"] != nothing
          logFileName = parsed_args["log"]
          logFileName = length(logFileName) < 5 ? "/tmp/RomeoLumber.log"  : logFileName 

          Lumberjack.configure(; modes = ["debug", "info", "warn", "error", "crazy"])
          Lumberjack.add_truck(LumberjackTruck(logFileName, "romeo-app"))
          Lumberjack.add_saw(Lumberjack.msec_date_saw)
          Lumberjack.log("debug", "starting main with args")
    end


    SemXMLSubscreen.setDebugLevels(true,0xFF)
    SubScreens.setDebugLevels(true,0xFF)
    RomeoLib.setDebugLevels(true,0xFF)
    realMain(onlyImg, pcamSel=pcamSel,  plotDim=plotDim, xml=xml )    
end

main(ARGS)

restoreErrStream(os)
close(ns)

