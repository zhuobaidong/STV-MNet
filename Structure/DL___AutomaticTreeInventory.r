# This is the code to create inventory automatically with pre-processed images from YOLOv3 and semantic segmentation with cityscape pretrained model.
AutomaticCode <-
    function(RawImage, YoloImage, YoloTable, SemsegImage, processDir, VH=2.5){
        print("进入函数")
      # Install and load essential packages for analysis
        pacman::p_load("imager", "tidyverse", "foreach", "segmented", "rmarkdown", "pander", "strucchange")
        print("Line8")
        # Extract Metadata from the file name of the Raw Image
        FileName <- gsub(".json.jpg", "", tail(unlist(strsplit(RawImage, "/")), 1))
        print(FileName)
        # 按照"_"切割字符串
        parts <- strsplit(FileName, "_")[[1]]
        
        # 从文件名提取信息
        Latitude_Longitude <- strsplit(parts[2], ",")[[1]]
        Latitude <- Latitude_Longitude[2]
        Longitude <- Latitude_Longitude[1]
        Heading_end <- strsplit(parts[4], "_")[[1]][1]
        Heading <- substr(Heading_end, 1, nchar(Heading_end)-4)
        print(Heading)
        # 构建DataFrame
        MetaData <- data.frame(
          Latitude = Latitude,
          Longitude = Longitude,
          Heading = Heading,
          pitch = 0
        )
        colnames(MetaData) <- c("Latitude", "Longitude", "Heading","pitch")
        print(MetaData)
        print("Line13")
        # Load images
        
        Orig_img <- load.image(RawImage)     # original image for image size
        Yolo_img <- load.image(YoloImage)     # original image for image size   加载YOLO目标检测的结果图像
        SmSg_img <- load.image(SemsegImage)   # Image from semantic segmentation

        # Load location of trees
        # (Bounding box from YOLO (left top right bottom class))
        Yolo_bbox <- read.csv(YoloTable)   #Yolo image中每个检测对象的ID，left，top，right，bottom，class
        
        # Information of original pictures
        W <- nrow(Orig_img) # Width of the picture
        H <- ncol(Orig_img) # Height of the picture
        VP <- (H+1)/2       # View point of the picture (!H+1 is required to point out the middel line of the image)
        print("Line26")
        # Required functions
        # Split image with imsub
        HorSpliter <- function(Img, BBox){ Img %>% imsub(x >= BBox[1] & x <= BBox[3])} #按照边界框对img进行垂直方向裁剪
        VerSpliter <- function(Img, BBox){ Img %>% imsub(y >= BBox[4] & y <= BBox[2])} #按照边界框对img进行水平方向裁剪

        
        TreeExtractor <-
          function(Img){
            IO <- Img
            R(IO)[which(!R(IO)[] * 255 == 128)] <- NA##图像中暗红色部分为树木，按颜色提取
            G(IO)[which(!G(IO)[] * 255 == 0)] <- NA
            B(IO)[which(!B(IO)[] * 255 == 0)] <- NA
            return(IO)
          }
        


        BaseDetector <-
          function(Img){
            # data <- R(Img)
            # print(data)
            # sumPixelValue <- colSums(data, na.rm=T) #计算非0像素的数量
            # print(sumPixelValue)
            # sumToV <- as.numeric(sumPixelValue, na.rm=T) #转为数值型向量
            # print(sumToV)
            # exceptValue <- sumToV %>% ifelse(. < 1, NA, .)#将小于1的小数设为na
            # print(exceptValue)
            # 计算图像中每一列非零像素的数量并转换为数值向量
            TreeOnly_col <- as.numeric(colSums(R(Img), na.rm=T)) %>% ifelse(. < 1, NA, .)
            # 检查是否存在非NA值
            if(all(is.na(TreeOnly_col))) {
              return(c(NA, NA, NA, NA))  # 如果全是NA值，则直接返回NA向量
            }
            # 寻找非零像素的最小索引位置，即树的底部位置
            TreeOnly_min <- ((TreeOnly_col * 0 + 1) * c(1:H)) %>% min(.,na.rm=T)
            # 寻找非零像素的最大索引位置，即树的顶部位置
            TreeOnly_max <- ((TreeOnly_col * 0 + 1) * c(1:H)) %>% max(.,na.rm=T)
            # 将树的最大索引位置作为基准点
            Base         <- TreeOnly_max
            # 设置基准点与树的顶部位置之间的距离为零
            Diff         <- 0       # 加一是为了包括基准点所在的像素单元
            # 返回基准点、距离、树的最小索引位置和树的最大索引位置
            return(c(Base, Diff, TreeOnly_min, TreeOnly_max))
          }
        
        
        # Image analysis tools
        StructureAnalyzer <- 
            function(out, H){
                print("进入StructureAnalyzer")
                # print(out)
                # Remove the row with zero vegetation pixels
                out.nonzero <- out[out[]>0]
                # print(out.nonzero)
                out.df      <- data.frame(PixW = out.nonzero)
                # print(out.df)
                out.df$PixH <- c(1:nrow(out.df)) 
                # print(out.df)
                cellNumber  <- as.numeric(gsub("X", "", row.names(out.df)))#把X去掉,cellNumber是行号
                # Check the first change point of the plot
                
                #剔除图像中不完整树木的检测
                print(length(out.df$PixW)>10)
                if (length(out.df$PixW)>10){
                    #突变点检测
                    out.cp <- strucchange::Fstats(PixW ~ 1, data=out.df)
                    VP       <- (H + 1) / 2
                    Tree_W   <- max(out.df$PixW, na.rm=T)                                           # Crown width
                    # print(Tree_W)

                    CellToVP <- ceiling(abs(cellNumber - VP))
                    # print(CellToVP)
                    Tree_H   <- sum(1/cos(asin(CellToVP/(H/2))), na.rm=T)                        # Tree Height   
                    # print(Tree_H)
                    BreakPt  <- out.cp$breakpoint
                    
                    # Create plot输出突变点检测示意图
                    plot(out.df$PixH, out.df$PixW, type="b", col="blue",xlab="CelltoBase", ylab="PixW", main="Structure Analyzer Plot")
                    
                    #显示突变点位置
                    # Add a vertical line at the breakpoint
                    abline(v = out.cp$breakpoint, col = "red", lty = 2)
                    
                    
                    Tree_BH  <- sum(1/cos(asin(CellToVP[1:BreakPt]/(H/2))), na.rm=T)                # Height below crown.
                    
                    
                    # DBH which is assumed to be a median width below crown.此时设为0.1，为10分位数
                    if (Tree_BH < length(out.df$PixW)) {
                      Tree_DBH <- quantile(out.df$PixW[1:Tree_BH], 0.1, na.rm = TRUE) 
                      print("Tree_DBH*******************************************************")
                      print(Tree_DBH)
                      
                      # 创建度量表
                      M <- data.frame(Tree_H, Tree_W, Tree_BH, Tree_DBH, TreeTop = min(cellNumber))
                      print(M)
                      return(M)
                    }
                    
                  }
                }
                

        # Combined function
        # VH: height of the camera
        TreeInventory  <- 
            function(Img, VH = 2.5, LocInfo = TreeLoc){ # VH of GSV is known as 2.5m 8.2 feet
              print("进入TreeInventory")
                W <- nrow(Img) # Width of the picture
                H <- ncol(Img) # Height of the picture
                f <- 0.54
                
                VP <- (H+1)/2      # View point of the picture
                print(nrow(LocInfo))
                BM <- foreach(i = 1:nrow(LocInfo), .combine=rbind) %do% {
                      print(i)
                      print(as.numeric(LocInfo[i,c(2:5)]))
                      plot(Img)

                      HorSplitImg     <- HorSpliter(Img, as.numeric(LocInfo[i,c(2:5)]))
                      # print(dim(HorSplitImg))
                      plot(HorSplitImg)
                      # 检查裁剪后的图像是否为空
                      
                      IndTreeOnly <- TreeExtractor(HorSplitImg)
                      # print(dim(IndTreeOnly))
                          
                      BaseDetector    <- BaseDetector(IndTreeOnly)
                      print("BaseDetector")
                      print(BaseDetector)
                      # 在处理之前检查BaseDetector是否全为NA
                      panduan <- all(is.na(BaseDetector))
  
                      print(!panduan)
                      if (!panduan  ) {
                        Base            <- BaseDetector[1]
                        Diff            <- BaseDetector[2]              
                        TreeTop         <- BaseDetector[3]             
                        TreeBottom      <- BaseDetector[4]
                        # Calculate the pixel width of the tree
                        BaseToVP        <- ceiling(abs((Base - VP))) #计算各树木像素到中线的距离 
                        # # print("BaseTOVP")
                        
                        #计算Wr
                        # #c(1:BaseToVP)对应公式中Di，1/cos(asin(c(1:BaseToVP)/(H/2)))对应Cv,i
                        CorrectedPixSum <- sum(1/cos(asin(c(1:BaseToVP)/(H/2))), na.rm=T)-BaseToVP
                        print(CorrectedPixSum)

                        PixelWidth      <- VH/CorrectedPixSum#Wr,算DBH    ####wr计算有问题，可考虑乘以深度/焦距，，最终基准像素宽度大概在0.6-0.8之间
                        print(PixelWidth)
                        # plot(IndTreeOnly)
                        
                        #对图像进行水平切割
                        TreeFit         <- VerSpliter(IndTreeOnly, as.numeric(LocInfo[i,c(2:5)]))
                        # plot(TreeFit)
                        # 1. 选择 TreeFit 的第一个维度的数据
                        subset_data <- TreeFit[,,1]
                        print("subset_data***********************************************************")
                        print(all(is.na(subset_data)))
                        if (!all(is.na(subset_data))){
                          # 2. 将取整后的数据转换为数据框
                          data_frame_data <- data.frame(ceiling(subset_data))
                          print("data_frame_data")
                          # 3. 对数据框的每一列应用 sum 函数，忽略缺失值
                          column_sums <- sapply(data_frame_data, function(x) sum(x, na.rm = TRUE))
                          # 4. 将结果反转
                          PixelCnt <- rev(column_sums)
                          # print(PixelCnt)
                          #PixelCnt       <- rev(sapply(data.frame(ceiling(TreeFit[,,1])), FUN = function(x){sum(x, na.rm=T)}))
                          #获取从树木底部到顶部的行号（修改）
                          Begin <- as.integer(LocInfo$bottom[i])+1
                          End <-as.integer(LocInfo$top[i])
                          a <-c(LocInfo$bottom[i]:LocInfo$top[i])
                          if (length(c(LocInfo$bottom[i]:LocInfo$top[i]))>length(PixelCnt)){
                            count=length(c(LocInfo$bottom[i]:LocInfo$top[i]))-length(PixelCnt)
                            a<-c(LocInfo$bottom[i]:(LocInfo$top[i]-count))
                            
                          }
                          # print(length(a))
                          names(PixelCnt) <- paste0("X",a )#记录每一行的列数，行数以在原始图像中的行号命名
                          print("PixelCnt*******************************************************************************")
                          
                          
                          print(all(is.na(PixelCnt)))#http://127.0.0.1:8597/graphics/plot_zoom_png?width=1200&height=900
                          # print(i)
                          PixelStr        <- StructureAnalyzer(PixelCnt, H)
                          print("StructureAnalyzer执行完毕！")
                          print(PixelStr)
                          # 确保结果不含有NA值
                          if (!is.null(PixelStr)){
                            result          <- (PixelStr %>% mutate(Tree_H = Tree_H, Tree_BH = Tree_BH))* PixelWidth#tree_H*Wr。
                            result$TreeTop  <- PixelStr$TreeTop
                            result$ID       <- i
                            print(result)
                            return(result)
                          }
                          
                        }
                        
                      }
                      
                }
                
            }

        # structure of the tree
        Tree.df <- TreeInventory(Img = SmSg_img, VH = 2.5, LocInfo = Yolo_bbox)
        print("TreeInventory执行完毕！")
        
          
        # Location of the tree
        Tree.Inv <- data.frame(Tree.df, Yolo_bbox[Tree.df$ID,])
        print(all(is.na(Tree.Inv)))
        
        if (!all(is.na(Tree.Inv))){
          Tree.Inv <- Tree.Inv %>%
            # The field of view (FOV) of Google street view is known as 127 degree and 63.5 is the half of the FOV.
            mutate(Dist  = abs(Tree_H - VH)/tan(asin(ceiling(abs(TreeTop-(H+1)/2))/(H/2)))) %>%
            # Horizontally, 1 pixel denotes the W/360 degree
            mutate(Angle = (as.numeric(MetaData$Heading) + (0.5 * (left + right) - W/2) * 360/W) %%360) %>%
            # Polar coordinate to cartesian coordinate
            mutate(rel_x = Dist * cos(Angle), rel_y = Dist * sin(Angle)) %>%
            # mutate(c_lat = as.numeric(MetaData$Latitude), c_lon = as.numeric(MetaData$Longitude))
            mutate(c_lat = MetaData$Latitude, c_lon = MetaData$Longitude)
          
          print(substr(FileName, 1, nchar(FileName)-4))
          write.csv(Tree.Inv, paste0(processDir, substr(FileName, 1, nchar(FileName)-4), "_result.csv") , row.names=F)
          return(Tree.Inv)
        }
        
    }
#mydataset
# # Specify the paths to your images and files

# 指定CSV文件夹路径
# csv为根据网络预测的边界框生成的指定格式的csv文件
root <- "E:/Suyingcai/STV_MNet"
inputData<-  paste0(root,"/data/input data/Structure/")
csv_folder <-  paste0(inputData,"csv")
print(file.exists(csv_folder))
# 获取CSV文件列表
csv_files <- list.files(csv_folder, pattern = "\\.csv$", full.names = TRUE)

processDir0 <- paste0(root,"/results/Structure calculation/results0.1/")
VH <- 2.5
# 遍历每个CSV文件
for (csv_file in csv_files) {
  # 构建文件名相关路径
  csv_file_name <- basename(csv_file)
  csv_file_name_no_ext <- tools::file_path_sans_ext(csv_file_name)
  YoloTable0 <- csv_file
  print(YoloTable0)
  #原街景影像
  RawImage0 <- paste0("E:/Suyingcai/changsha/changsha.zip/changsha/", csv_file_name_no_ext, ".jpg")
  print(RawImage0)
  #网络预测街景图
  YoloImage0 <- paste0(root,"/results/STV_MNet/predict_changsha/", csv_file_name_no_ext, ".jpg")
  print(YoloImage0)
  #网络预测mask图
  SemsegImage0 <- paste0(root,"/data/input data/Structure/mask/", csv_file_name_no_ext, ".png")
  print(SemsegImage0)

  
  
  file.exists(RawImage0)
  file.exists(YoloImage0)
  file.exists(YoloTable0)
  file.exists(SemsegImage0)
  result_file <- paste0(processDir0, csv_file_name_no_ext, "_resultTest.csv")
  print(result_file)
  if (file.exists(result_file)) {
    print("文件存在")
  } else {
  
    # Call the functiona
    result <- AutomaticCode(RawImage0, YoloImage0, YoloTable0, SemsegImage0, processDir0, VH)
    
    # Print the result if needed
    print(result)
  }
}