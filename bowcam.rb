
# Add a menu item to launch our plugin.
UI.menu("PlugIns").add_item("Genreate Bow Cam") {
  generator = Generator.new()
  generator.generate()  
}

def max (a,b)
  a>b ? a : b
end

def add(a, b)
  return [a[0] + b[0], a[1] + b[1]]
end

def sub(a, b)
  return [a[0] - b[0], a[1] - b[1]]
end

def mult(a, scalar)
  return [a[0]*scalar, a[1]*scalar]
end

def dotProd(a, b)
  return a[0]*b[0] + a[1]*b[1]
end

def vectorsAngle(a, b)
  if (a[0] == b[0] and a[1] == b[1])
    return 0
  else
    return Math.acos(dotProd(a, b) / (length(a) * length(b)))
  end
end
 
def length(a)
  length = Math.sqrt(a[0] * a[0] + a[1] * a[1])
end

def normalize(a)
  l = length(a)
  return [a[0]/l, a[1]/l]  
end

def x(point)
  return point[0]
end

def y(point)
  return point[1]
end

def z(point)
  return point[2]
end

def polarX(polar)
  return Math.cos(polar[0]) * polar[1]
    #cos(v) = y / r
end

def polarY(polar)
  return Math.sin(polar[0]) * polar[1]
end
  
def polarToPoint2D(polar)
    #point = Array.new(2)
    #point[0] = polarX(polar)
    #point[1] = polarY(polar)
    return [polarX(polar), polarY(polar)]
end

def plotGraph(origo, points)
  model = Sketchup.active_model
  entities = model.entities
  toMM = 1/25.4
  i = 0
  lastPoint = 0
  draw = true
  while i < points.length
    point = points[i]
    if (i > 0 and draw)
      entities.add_line [(origo[0] + point[0])*toMM, (origo[1] + point[1])*toMM, 0], [(origo[0] + lastPoint[0])*toMM, (origo[1] + lastPoint[1])*toMM, 0]
    end
    # draw = !draw
    lastPoint = point
    i = i + 1 
  end
end


def plotStickGraph(origo, points)
  model = Sketchup.active_model
  entities = model.entities
  toMM = 1/25.4
  i = 0
  while i < points.length
    point = points[i]
    entities.add_line [origo[0]*toMM, origo[1]*toMM, 0], [(origo[0] + point[0])*toMM, (origo[1] + point[1])*toMM, 0]
    i = i + 1 
  end
end


class Generator
  def initialize()

    # Spring and power stroke
    # @springStrokeStartCm = 40.0 # > 0 is pretension
    # @springStrokeEndCm = 100.0
    @springStrokeStartCm = 60.0 # > 0 is pretension
    @springStrokeEndCm = 120.0
    
    @springForcePerCm = 1.0
    @powerStroke =  @springStrokeEndCm - @springStrokeStartCm

    # Input stroke
    @inputStroke = @powerStroke

    # Target input force. Constant force.
    @inputEnergy = @springForcePerCm * ((@springStrokeStartCm + @springStrokeEndCm) / 2) * @powerStroke
    @constantInputForce = @inputEnergy / @inputStroke 

    # Lever angles (connected to spring/input, angle from hub to spring tangent)
    @springAngle = 0.0
    @inputAngle = Math::PI * 1.0

    # Lever setup
    # @constantInputLever = nil
    # @constantSpringLever = nil
    @constantLeverSum = 46.0
    # @constantLeverSumDelta = 3.0
    # @constantLeverSumDeltaDelta = 0.05

    @springStartHingeOffset = 0 #10.0
  end

  def springForce(currentDrawLength) 
    return @springStrokeStartCm*@springForcePerCm + currentDrawLength*@springForcePerCm
  end

  def forceFactor(currentDrawLength) 
    return springForce(currentDrawLength) / @constantInputForce
  end

  def speedFactor(currentDrawLength)
    return 1 / forceFactor(currentDrawLength)
  end

  def generate() 
    plotGraphs([100, 0])
    drawCam([0, 0])
  end

  def getStartLeversLengths(forceFactor)
    springLeverLength = @constantLeverSum / (forceFactor + 1)
    inputLeverLength = @constantLeverSum - springLeverLength
    # @constantLeverSum = @constantLeverSum - @constantLeverSumDelta
    # @constantLeverSumDelta = max(@constantLeverSumDelta - @constantLeverSumDeltaDelta, 0);
    return [inputLeverLength, springLeverLength]
  end

  def canFindInputHingePoint(lastInputLeverPolar, lastInputHinge, deltaAngle, inputLeverLength, inputLeverPolar)
    # Find anchor point for input 
    distA = Math.cos(deltaAngle) * lastInputLeverPolar[1]
    distB = inputLeverLength - distA
    distC = Math.tan(deltaAngle) * lastInputLeverPolar[1]
    distD = distB / Math.tan(deltaAngle)
    distLastInputLeverToNewHinge = distC + distD
    distLastInputLeverToHinge = length(sub(lastInputHinge, polarToPoint2D(lastInputLeverPolar)))
    return ((distB >= 0) and (distLastInputLeverToHinge < distLastInputLeverToNewHinge))
  end

  def inputHingePoint(lastInputLeverLength, deltaAngle, inputLeverPolar, inputLeverLength, inputAngle)
    # Find anchor point for input 
    distA = Math.cos(deltaAngle) * lastInputLeverLength
    distB = inputLeverLength - distA
    angleA = Math::PI - Math::PI/2 - deltaAngle
    distInputLeverToHinge = Math.tan(angleA) * distB
    inputLeverToHinge = polarToPoint2D([inputAngle - (Math::PI / 2), distInputLeverToHinge])
    return add(polarToPoint2D(inputLeverPolar), inputLeverToHinge)
  end

  def drawCam(origo) 
    print "\ngenerating cam\n"

    forceFactorError = 0

    inputAngle = @inputAngle
    springAngle = @springAngle

    hingedSpringCable = 0.0
    totalSpringCable = 0.0

    # Hinges
    inputHinges = Array.new(0)
    springHinges = Array.new(0)

    # Levers
    springLeversPolar = Array.new(0) 
    inputLeversPolar = Array.new(0)

    forceFactorCurve = Array.new(0)

    drawStepSize = 1.0
    currentDrawLength = 0.0
    while((currentDrawLength <= 100) and (currentDrawLength <= @powerStroke))
      print "\n"
      print "currentDrawLength: ", currentDrawLength, "\n"
      currentForceFactor = forceFactor(currentDrawLength)
      springLeverPolar = nil
      inputLeverPolar = nil

      if (currentDrawLength == 0)
        totalSpringCable = @springStartHingeOffset

        levers = getStartLeversLengths(currentForceFactor)
        inputLeverLength  = levers[0]
        springLeverLength = levers[1]
        # print levers, "\n"

        # Define the new point on the curve
        springLeverPolar = [springAngle, springLeverLength]
        inputLeverPolar = [inputAngle, inputLeverLength]
        
        # Draw orientation hints
        # springPoint = polarToPoint2D(springLeverPolar)
        # springVector = polarToPoint2D([springAngle - (Math::PI / 2), @powerStroke])
        # inputPoint = polarToPoint2D(inputLeverPolar)
        # inputVector = polarToPoint2D([inputAngle + (Math::PI / 2), @inputStroke])
        # plotGraph(origo, [[0, 0], springPoint, add(springPoint, springVector)])
        # plotGraph(origo, [[0, 0], inputPoint, add(inputPoint, inputVector)])
        
        # Input levers and anchor curve
        inputHinges.push(polarToPoint2D(inputLeverPolar))
        springHinges.push(add(polarToPoint2D(springLeverPolar), polarToPoint2D([springAngle + Math::PI / 2, @springStartHingeOffset])))
        springLeversPolar.push(springLeverPolar)
        inputLeversPolar.push(inputLeverPolar)

        forceFactorCurve.push([currentDrawLength, currentForceFactor])
      else
        ## Last spring lever and hinge
        lastSpringLeverPolar = springLeversPolar.last
        lastSpringLever = polarToPoint2D(lastSpringLeverPolar)
        lastSpringAngle = lastSpringLeverPolar[0]
        lastSpringLeverLength = lastSpringLeverPolar[1]
        lastSpringHinge = springHinges.last

        ## Last input lever and hinge
        lastInputLeverPolar = inputLeversPolar.last
        lastInputAngle = lastInputLeverPolar[0]
        lastInputLeverLength = lastInputLeverPolar[1]

        ## Increase cable
        totalSpringCable = totalSpringCable + drawStepSize
       
        # Spring lever
        deltaAngle = nil
        inputLeverLength = nil
        springLeverPolar = nil
        springLeverLength = nil
        
        ## Find a suitable spring lever length
        lastHingeVector = sub(lastSpringLever, lastSpringHinge)
        lastHingeVectorLength = length(lastHingeVector)
        normalizedLastHingeVector = normalize(lastHingeVector)
        unhingedSpringCable = totalSpringCable - hingedSpringCable
        print "unhingedSpringCable: ", unhingedSpringCable, "\n"

        step = 0
        done = false
        while (step < 10 && !done)
          additionallyHingedCable = 0
          # print normalizedLastHingeVector, "\n"
          if (lastHingeVectorLength > 0)
            print "moving hinge...\n"
            additionallyHingedCable = (step / 10.0) * lastHingeVectorLength
            candidateHinge = add(lastSpringHinge, mult(normalizedLastHingeVector, additionallyHingedCable))
          else 
            candidateHinge = lastSpringHinge
          end
          candidateRadius = length(candidateHinge)
          candidateHingeLastLeverAngle = vectorsAngle(candidateHinge, lastSpringLever)
          
          # print "Data:\n"
            # print unhingedSpringCable/candidateRadius, "\n"
          # print unhingedSpringCable, "\n"
          # print "candidateRadius: ", candidateRadius, "\n"
          # print candidateRadius, "\n"
          # print "unhingedSpringCable: ", unhingedSpringCable, "\n"
          # print "candidateHingeLastLeverAngle: ", candidateHingeLastLeverAngle, "\n"
          # if (unhingedSpringCable/candidateRadius <= 1)
          # end

          candidateHingeToLeverAngle = Math.asin(unhingedSpringCable/candidateRadius)
          deltaAngle = candidateHingeToLeverAngle - candidateHingeLastLeverAngle
          springLeverLength = candidateRadius * Math.cos(candidateHingeToLeverAngle)  
          # print "candidateHingeToLeverAngle: ", candidateHingeToLeverAngle, "\n"
          print "deltaAngle: ", deltaAngle, "\n"
          springAngle = springAngle - deltaAngle
          springLeverPolar = [springAngle, springLeverLength]
          print "springLeverPolar: ", springLeverPolar, "\n"
          inputLeverLength = springLeverLength * currentForceFactor            

          # Input lever
          inputAngle = inputAngle - deltaAngle;
          inputLeverPolar = [inputAngle, inputLeverLength]

          if (true or canFindInputHingePoint(lastInputLeverPolar, inputHinges.last, deltaAngle, inputLeverLength, inputLeverPolar))
            # print "done, found one!"
            done = true
          end

          step = step + 1
        end
        print "found one in ", step - 1, " steps: ", done, ".\n"
        springHinges.push(candidateHinge)
        springLeversPolar.push(springLeverPolar)

        # if ((currentDrawLength > 0.0) and (currentDrawLength < 58.0)) 
          # Force hinge at new lever
          hingedSpringCable = hingedSpringCable + unhingedSpringCable
          springHinges.push(polarToPoint2D(springLeverPolar))
        # else 
        #   hingedSpringCable = hingedSpringCable + additionallyHingedCable #todo
        # end

        # # Add cable turn hinge
        # cableSegment = 0.1
        # cableSegmentPolar = [springLeverPolar[0] - (Math::PI / 2), cableSegment]
        # print "cableSegmentPolar: ", cableSegmentPolar, "\n"
        # springHinges.push(add(springHinges.last, polarToPoint2D(cableSegmentPolar)))
        # hingedSpringCable = hingedSpringCable + cableSegment


        # Push to curves
        inputHinges.push(inputHingePoint(lastInputLeverLength, deltaAngle, inputLeverPolar, inputLeverLength, inputAngle))
        inputLeversPolar.push(inputLeverPolar)

        forceFactorCurve.push([currentDrawLength, currentForceFactor])
      end
      
      currentDrawLength = currentDrawLength + drawStepSize
    end

    plotGraph(origo, inputHinges)
    plotGraph(origo, springHinges)
    # print springHinges
    plotStickGraph(origo, springLeversPolar.map { |polar| polarToPoint2D(polar) })
    plotStickGraph(origo, inputLeversPolar.map { |polar| polarToPoint2D(polar) })
  end

  def plotGraphs(origo) 
    springPowerCurve = Array.new(0) 
    forceFactorCurve = Array.new(0) 
    targetCurve = Array.new(0) 

    # Force and gear curve
    drawStepSize = 1.0
    currentDrawLength = 0
    while(currentDrawLength <= @powerStroke)
      springPowerCurve.push([currentDrawLength, springForce(currentDrawLength)])
      # print " --- \n"
      # print "currentDrawLength: ", currentDrawLength, ", "
      # print "springForce: ", springForce(currentDrawLength), ", " 
      if (springForce(currentDrawLength) > 0)
        # print "forceFactor: ", forceFactor(currentDrawLength)
        #UI.messagebox(@constantInputForce)
        forceFactorCurve.push([currentDrawLength, forceFactor(currentDrawLength)])
      end
      currentDrawLength = currentDrawLength + drawStepSize
    end

    # Target curve
    targetCurve.push([0, @constantInputForce])
    targetCurve.push([@powerStroke, @constantInputForce])

    plotGraph(origo, springPowerCurve)
    plotGraph(origo, forceFactorCurve)
    plotGraph(origo, targetCurve)
  end
end