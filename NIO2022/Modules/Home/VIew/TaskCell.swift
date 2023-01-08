//
//  TaskCell.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/28.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIOMan

protocol TaskCellDelegate : class {
    func taskCellDidSelected(task:Task?,selected: Bool,indexPath: IndexPath?)
}

class TaskCell: UITableViewCell {

    @IBOutlet weak var configLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var updataLabel: UILabel!
    @IBOutlet weak var downdataLabel: UILabel!
    @IBOutlet weak var countLabel: UILabel!
    @IBOutlet weak var lineView: UIView!
    
    weak var delegate:TaskCellDelegate?
    var indexPath: IndexPath?
    var tap:UITapGestureRecognizer?
    private var _isLast:Bool = false
    var isLast:Bool{
        set{
            _isLast = newValue
            lineView.isHidden = _isLast
        }
        get{
            return _isLast
        }
    }
    
    var _task:Task?
    var task:Task?{
        set{
            _task = newValue
            updateUI()
        }
        get{
            return _task
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
    
    }

    
    func updateUI(){
        configLabel.text = task?.rule_name
        configLabel.font = Font16
        if let ts = task?.start_time {
            timeLabel.text = "\(Date(timeIntervalSince1970: TimeInterval(truncating: ts)).CurrentStingTime)"
        }
        updataLabel.text = task?.out_bytes.floatValue.bytesFormatting()//"\(task?.uploadTraffic ?? 0)B"
        downdataLabel.text = task?.in_bytes.floatValue.bytesFormatting()//"\(task?.downloadFlow ?? 0)B"
        countLabel.text = "\(task?.conn_count ?? 0)"
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        if editing {
            if tap == nil {
                tap = UITapGestureRecognizer(target: self, action: #selector(viewDidTouch))
                addGestureRecognizer(tap!)
            }
        }else{
            if tap != nil {
                removeGestureRecognizer(tap!)
                tap = nil
            }
        }
    }
    
    @objc func viewDidTouch(){
        delegate?.taskCellDidSelected(task: task, selected: isSelected,indexPath: indexPath)
    }
}
